# frozen_string_literal: true

class Redis
  module Async
    module Pool
      # redis-rb's Redis::Cluster over a pool of connections per node that fibers share, where Redis::Cluster
      # serializes everything. With an async pool, its commands to several nodes run concurrently in fibers.
      #
      #   redis = Redis::Async::Pool::ClusterClient.new(nodes: ["redis://node-1:6379"], pool: { size: 16 })
      class ClusterClient < ::Redis::Cluster
        # @parameter options [Hash] Redis::Cluster.new's options, and pool: (see Pool::DEFAULT_POOL, per node).
        #   concurrency: defaults to { model: :async } (a FiberWorker) with an async pool.
        def initialize(options = {})
          options = options.dup
          @pool_options = Pool.pool_options(options.delete(:pool))
          options[:concurrency] ||= { model: :async } if @pool_options[:async]
          super(options)
        end

        def dup
          self.class.new(@options.merge(pool: @pool_options))
        end

        private

        # The config's #new_pool would drop pool options other than size: and timeout: (e.g. async:).
        def initialize_client(options)
          config = ::RedisClient.cluster(**options, protocol: 2, client_implementation: ::Redis::Cluster::Client)
          config.new_client(pool: @pool_options)
        end

        def synchronize
          yield(@client)
        end

        def send_command(command, &block)
          @client.call_v(command, &block)
        rescue ::RedisClient::Error => error
          ::Redis::Cluster::Client.translate_error!(error)
        end

        def send_blocking_command(command, timeout, &block)
          @client.blocking_call_v(timeout, command, &block)
        rescue ::RedisClient::Error => error
          ::Redis::Cluster::Client.translate_error!(error)
        end
      end
    end
  end
end
