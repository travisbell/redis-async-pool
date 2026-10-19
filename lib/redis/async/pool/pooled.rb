# frozen_string_literal: true

class Redis
  module Async
    module Pool
      # redis-client's connection pool, with what redis-rb's Redis also calls on its client (a single connection's
      # Redis::Client) answered from the pool's configuration.
      class Pooled < ::RedisClient::Pooled
        def initialize(...)
          super
          @connected = false
        end

        def with(...)
          @connected = true
          super
        end

        def close
          @connected = false
          super
        end

        # Whether it has connected since it was opened (or last closed).
        def connected?
          @connected
        end

        def disable_reconnection
          with { |client| client.disable_reconnection { yield } }
        end

        def server_url
          config.server_url
        end

        def host
          config.host unless config.path
        end

        def port
          config.port unless config.path
        end

        def path
          config.path
        end

        def db
          config.db
        end

        def timeout
          config.read_timeout
        end

        def inherit_socket!; end
      end
    end
  end
end
