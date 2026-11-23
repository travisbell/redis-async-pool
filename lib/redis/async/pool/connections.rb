# frozen_string_literal: true

class Redis
  module Async
    module Pool
      # connection_pool's interface, as redis-client's RedisClient::Pooled uses it, over an
      # Async::Pool::Controller: so redis-client's pools (including each cluster node's) can be async-pool
      # pools, which pool metrics hooked into Async::Pool::Controller measure.
      #
      # Fibers only: async-pool isn't thread-safe. Outside a reactor, each checkout runs in one of its own.
      class Connections
        # async-pool's controller without its gardener. With no policy (none is set here), the gardener's task
        # only wakes on every release, a context switch per command. It also closes the pool when the reactor it
        # started in finishes, so outside a reactor, where each checkout runs in a reactor of its own, every
        # command would reconnect.
        class Controller < ::Async::Pool::Controller
          # Its Set#any? goes through Enumerable, allocating on every command.
          def available?
            !@available.empty?
          end

          protected

          def start_gardener; end
        end

        # A pooled redis-client connection.
        class Resource < ::Async::Pool::Resource
          attr_reader :client

          def initialize(client)
            super()
            @client = client
          end

          def close
            @client.close
            super
          end
        end

        # Commands that change or block the connection they run on, which never share a pipeline with other fibers'.
        UNPIPELINED = %w[
          multi exec discard watch unwatch select auth hello client reset quit monitor
          subscribe unsubscribe psubscribe punsubscribe ssubscribe sunsubscribe
          sync psync replconf readonly readwrite asking wait waitaof migrate debug shutdown
          blpop brpop brpoplpush blmove blmpop blmovem bzpopmin bzpopmax bzmpop bzmove xread xreadgroup
        ].flat_map { |name| [name, name.upcase, name.to_sym, name.upcase.to_sym] }.to_h { |name| [name, true] }.freeze

        # A command waiting to go out in a pipeline. It's also what wakes its fiber, from the scheduler's ready queue:
        # only while the fiber waits for it (it's parked), so a wakeup the fiber no longer needs (e.g. it was stopped
        # first) can't resume it from whatever it waits for next.
        Request = Struct.new(:command, :fiber, :deadline, :value, :error, :done, :lead, :parked) do
          def alive?
            parked
          end

          def transfer
            fiber.transfer
          end
        end

        class CheckoutTimeout < ::Async::TimeoutError; end

        attr_reader :size, :controller

        # @parameter tags [Hash] The pool's tags (e.g. for metrics), to which the server's URL is added.
        # @parameter auto_pipeline [Boolean] Whether fibers' commands that find every connection busy go out together.
        def initialize(size:, server_url:, timeout: 5, tags: nil, auto_pipeline: true, &factory)
          @size = size
          @timeout = timeout
          @auto_pipeline = auto_pipeline
          @controller = Controller.wrap(limit: size, tags: { endpoint: server_url }.merge(tags || {})) { Resource.new(factory.call) }
          # Thread#[] is per fiber (and, unlike Fiber[], not inherited by the fibers it starts).
          @held_key = :"redis_async_pool_held_#{object_id}"
          @pending = []
        end

        def pipelines?(command)
          return false unless @auto_pipeline

          name = command.first
          !(UNPIPELINED[name] || (name.is_a?(String) && UNPIPELINED[name.downcase]))
        end

        # Sends a command as owner (a RedisClient::Pooled) would, over a free connection. If every connection is
        # busy, it waits with the other fibers' commands that found them busy, and the first of those fibers sends
        # them all in one pipeline when a connection frees up: a round trip, and a read and a write, for all of them.
        # Each reply, error or reply block is returned, raised or called in its own fiber.
        def call_v(command, owner, &block)
          held = Thread.current[@held_key]
          return held.client.call_v(command, &block) if held

          Sync do |task|
            if @pending.empty? && free?
              resource = @controller.acquire
              begin
                prepare(resource.client, owner).call_v(command, &block)
              ensure
                @controller.release(resource)
              end
            else
              request = Request.new(command, Fiber.current, monotonic + @timeout)
              request.lead = @pending.empty?
              @pending << request
              send_in_pipeline(request, task, owner)

              raise request.error if request.error

              block ? yield(request.value) : request.value
            end
          end
        end

        # Yields a connection, raising ConnectionPool::TimeoutError (which redis-client expects) if none is free in
        # time. Like connection_pool, it's re-entrant: a fiber that already holds one gets it again, which
        # redis-cluster-client relies on (e.g. a #watch block's commands go through the router to the same node).
        def with(timeout: @timeout)
          held = Thread.current[@held_key]
          return yield(held.client) if held

          Sync do |task|
            resource = checkout(task, timeout)

            begin
              Thread.current[@held_key] = resource
              yield resource.client
            ensure
              Thread.current[@held_key] = nil
              @controller.release(resource)
            end
          end
        end

        def shutdown
          @controller.close
        end

        private

        # Only waiting for a connection is timed, so taking a free one doesn't arm a timer. (Taking one can still
        # wait for another fiber to finish connecting, which its connect timeout bounds.) Its own exception tells its
        # timeout from one around the caller's command.
        def checkout(task, timeout, waited: timeout)
          return @controller.acquire if free?

          begin
            raise CheckoutTimeout unless timeout.positive?

            task.with_timeout(timeout, CheckoutTimeout) { @controller.acquire }
          rescue CheckoutTimeout
            raise ::ConnectionPool::TimeoutError, "Waited #{waited} sec, 0/#{@size} available"
          end
        end

        # Whether a connection can be taken without waiting for another to be released: one is idle, or there's room
        # for a new one.
        def free?
          @controller.available? || @controller.size < @size
        end

        # What RedisClient::Pooled#with sets on every connection it hands out.
        def prepare(client, owner)
          client.connect_timeout = owner.connect_timeout
          client.read_timeout = owner.read_timeout
          client.write_timeout = owner.write_timeout
          client
        end

        # The fiber that queued the first pending request leads: it waits for a connection (in the controller's queue,
        # with the fibers that check connections out) and sends every request pending by then. The others wait for
        # their reply, or to lead if the leader gives up first.
        def send_in_pipeline(request, task, owner)
          until request.done
            if request.lead
              lead(request, task, owner)
            else
              follow(request)
            end
          end
        end

        def follow(request)
          # The leader, a leader giving up, or a pipeline's task pushes the request onto the scheduler's ready queue.
          request.parked = true
          Fiber.scheduler.transfer
        rescue Exception
          # Stopped or timed out by its task: if it's still pending it leaves, passing on the lead if it had it. If its
          # pipeline has gone out, its command still runs.
          promote(@pending.first) if @pending.delete(request) && request.lead
          raise
        ensure
          request.parked = false
        end

        # A leader's own command goes out in its fiber. Others' go out in a task of the reactor's, which stopping or
        # timing out the leader (e.g. as its request is cancelled) doesn't interrupt: the leader then waits as they do.
        def lead(request, task, owner)
          resource = checkout(task, request.deadline - monotonic, waited: @timeout)
          batch = @pending
          @pending = []
          request.lead = false

          if batch.size == 1
            send_pipeline(resource, batch, owner)
          else
            sending = resource
            resource = nil
            ::Async::Task.new(Fiber.scheduler, annotation: "redis-async-pool pipeline") do
              send_pipeline(sending, batch, owner)
            ensure
              @controller.release(sending)
            end.run
          end
        ensure
          if resource
            @controller.release(resource)
          elsif request.lead
            # Its wait timed out or was interrupted. Those that queued after it get to wait as long as it could.
            @pending.delete(request)
            promote(@pending.first)
          end
        end

        def promote(request)
          return unless request

          request.lead = true
          wake(request)
        end

        def send_pipeline(resource, batch, owner)
          Thread.current[@held_key] = resource
          client = prepare(resource.client, owner)
          if batch.size == 1
            sent = batch
            results = [call(client, batch.first.command)]
          else
            sent = []
            results = client.pipelined(exception: false) do |pipeline|
              batch.each do |request|
                pipeline.call_v(request.command)
                sent << request
              rescue StandardError => error
                # An invalid argument fails its own command, as RedisClient#call_v would, which stays out of the pipeline.
                request.error = error
                finish(request)
              end
            end
          end

          sent.each_with_index do |request, index|
            result = results[index]
            if result.is_a?(::RedisClient::Error)
              # Its next error would be another fiber's.
              result._set_next_error(nil)
              request.error = result
            else
              request.value = result
            end
            finish(request)
          end
        rescue Exception => error
          # The connection's (or e.g. a middleware's) error, or, if the pipeline's task was stopped (with its reactor),
          # as if the connection had been lost: redis-client closes a connection interrupted while it awaited replies.
          shared = error.is_a?(StandardError) ? error : ::RedisClient::ConnectionError.new("The pipeline was interrupted: #{error.class}")
          batch.each do |request|
            next if request.done

            request.error = request.fiber.equal?(Fiber.current) ? error : shared
            finish(request)
          end
          # In a pipeline's task, its commands' fibers have the error.
          raise if batch.size == 1 || !error.is_a?(StandardError)
        ensure
          Thread.current[@held_key] = nil
        end

        # A batch of one goes out as the single command it is, as middlewares would otherwise see a pipeline of one.
        def call(client, command)
          client.call_v(command)
        rescue ::RedisClient::CommandError => error
          error
        end

        def finish(request)
          request.done = true
          wake(request)
        end

        # Same-thread wakeups don't need the selector's wakeup (a write to its pipe), which Fiber::Scheduler#unblock does.
        def wake(request)
          Fiber.scheduler.push(request) if request.parked
        end

        def monotonic
          Process.clock_gettime(Process::CLOCK_MONOTONIC)
        end
      end

      # Builds redis-client's pools with Connections when their options say async: true (and connection_pool's
      # otherwise, without the options it doesn't know).
      # Its single commands go through Connections#call_v, which pipelines them when connections are busy.
      module AsyncPooled
        def call_v(command, &block)
          pool = self.pool
          return super unless pool.is_a?(Connections) && pool.pipelines?(command)

          begin
            pool.call_v(command, self, &block)
          rescue ::ConnectionPool::TimeoutError => error
            raise ::RedisClient::CheckoutTimeoutError, "Couldn't checkout a connection in time: #{error.message}"
          end
        end

        private

        def new_pool
          options = @pool_kwargs
          return Connections.new(server_url: @config.server_url, **options.except(:async)) { @config.new_client } if options[:async]

          @pool_kwargs = options.except(:async, :tags, :auto_pipeline)
          super
        end
      end
    end
  end
end
