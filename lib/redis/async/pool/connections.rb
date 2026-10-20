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

        attr_reader :size, :controller

        # @parameter tags [Hash] The pool's tags (e.g. for metrics), to which the server's URL is added.
        def initialize(size:, server_url:, timeout: 5, tags: nil, &factory)
          @size = size
          @timeout = timeout
          @controller = Controller.wrap(limit: size, tags: { endpoint: server_url }.merge(tags || {})) { Resource.new(factory.call) }
          # Thread#[] is per fiber (and, unlike Fiber[], not inherited by the fibers it starts).
          @held_key = :"redis_async_pool_held_#{object_id}"
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
        # wait for another fiber to finish connecting, which its connect timeout bounds.)
        def checkout(task, timeout)
          return @controller.acquire if @controller.available?

          begin
            task.with_timeout(timeout) { @controller.acquire }
          rescue ::Async::TimeoutError
            raise ::ConnectionPool::TimeoutError, "Waited #{timeout} sec, 0/#{@size} available"
          end
        end
      end

      # Builds redis-client's pools with Connections when their options say async: true (and connection_pool's
      # otherwise, without the options it doesn't know).
      module AsyncPooled
        private

        def new_pool
          options = @pool_kwargs
          return Connections.new(server_url: @config.server_url, **options.except(:async)) { @config.new_client } if options[:async]

          @pool_kwargs = options.except(:async, :tags)
          super
        end
      end
    end
  end
end
