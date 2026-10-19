# frozen_string_literal: true

class Redis
  module Async
    module Pool
      # redis-rb's Redis over a pool of connections that fibers share, where Redis serializes everything on its
      # one connection. A #watch block sends its fiber's commands over one connection, as WATCH requires.
      #
      #   redis = Redis::Async::Pool::Client.new(url: "redis://localhost:6379", pool: { size: 16 })
      class Client < ::Redis
        # @parameter options [Hash] Redis.new's options, and pool: (see Pool::DEFAULT_POOL).
        def initialize(options = {})
          options = options.dup
          @pool_options = Pool.pool_options(options.delete(:pool))
          # Thread#[] is per fiber (and, unlike Fiber[], not inherited by the fibers it starts).
          @pinned_key = :"redis_async_pool_pinned_#{object_id}"
          super(options)
        end

        def watch(*keys, &block)
          return super unless block
          return super if pinned

          @client.with do |connection|
            Thread.current[@pinned_key] = connection
            super(*keys, &block)
          ensure
            Thread.current[@pinned_key] = nil
            release_watch(connection)
          end
        end

        def dup
          self.class.new(@options.merge(pool: @pool_options))
        end

        private

        def initialize_client(options)
          Pooled.new(::Redis::Client.config(**options), **@pool_options)
        end

        def pinned
          Thread.current[@pinned_key]
        end

        # A block that didn't end in EXEC or DISCARD (which unwatch) would leave the connection watching for its
        # next user, so it's UNWATCHed. That costs a round trip, which redis-rb's one connection doesn't need. If
        # it fails, the connection is closed (it reconnects on its next use) rather than hiding the block's error.
        def release_watch(connection)
          connection.call_v(["UNWATCH"]) if connection.connected?
        rescue ::RedisClient::Error, ::Redis::BaseError
          connection.close
        end

        def synchronize
          yield(pinned || @client)
        end

        def send_command(command, &block)
          (pinned || @client).call_v(command, &block)
        rescue ::RedisClient::Error => error
          ::Redis::Client.translate_error!(error)
        end

        def send_blocking_command(command, timeout, &block)
          (pinned || @client).blocking_call_v(timeout, command, &block)
        rescue ::RedisClient::Error => error
          ::Redis::Client.translate_error!(error)
        end
      end
    end
  end
end
