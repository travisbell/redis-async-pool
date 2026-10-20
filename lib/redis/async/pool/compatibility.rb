# frozen_string_literal: true

class Redis
  module Async
    module Pool
      # Checks that the installed redis-rb, redis-client, redis-cluster-client and async-pool still have the
      # internals redis-async-pool builds on.
      module Compatibility
        # What the clients override in redis-rb's Redis.
        REDIS_PRIVATE_METHODS = [:initialize_client, :synchronize, :send_command, :send_blocking_command].freeze
        # What the pools use of async-pool.
        CONTROLLER_METHODS = [:acquire, :available?, :release, :close].freeze

        class << self
          def check!
            missing = []

            REDIS_PRIVATE_METHODS.each do |method|
              missing << "Redis##{method}" unless ::Redis.private_method_defined?(method)
            end

            missing << "Redis::Client.translate_error!" unless ::Redis::Client.respond_to?(:translate_error!)
            missing << "Redis::Cluster::Client.translate_error!" unless ::Redis::Cluster::Client.respond_to?(:translate_error!)

            # AsyncPooled replaces how RedisClient::Pooled builds its pool from its options and config.
            missing << "RedisClient::Pooled#new_pool" unless ::RedisClient::Pooled.private_method_defined?(:new_pool)
            missing << "RedisClient::Pooled#with" unless ::RedisClient::Pooled.method_defined?(:with)
            pooled = ::RedisClient::Pooled.new(::RedisClient.config, size: 1)
            [:@pool_kwargs, :@config].each do |variable|
              missing << "RedisClient::Pooled #{variable}" unless pooled.instance_variable_defined?(variable)
            end

            # ClusterClient passes pool: and concurrency: through the config to RedisClient::Cluster.
            missing << "RedisClient::ClusterConfig#new_client" unless ::RedisClient::ClusterConfig.method_defined?(:new_client)
            missing << "RedisClient::Cluster.new(pool:, concurrency:)" unless keywords?(::RedisClient::Cluster.instance_method(:initialize), :pool, :concurrency)

            # FiberWorker is a concurrent worker built on redis-cluster-client's Group and its tasks.
            worker = ::RedisClient::Cluster::ConcurrentWorker
            missing << "RedisClient::Cluster::ConcurrentWorker.create" unless worker.respond_to?(:create)
            if defined?(worker::Group::Task)
              missing << "RedisClient::Cluster::ConcurrentWorker::Group.new(worker:, queue:, size:)" unless keywords?(worker::Group.instance_method(:initialize), :worker, :queue, :size)
              [:push, :each, :close].each do |method|
                missing << "RedisClient::Cluster::ConcurrentWorker::Group##{method}" unless worker::Group.method_defined?(method)
              end
              missing << "RedisClient::Cluster::ConcurrentWorker::Group::Task#exec" unless worker::Group::Task.method_defined?(:exec)
            else
              missing << "RedisClient::Cluster::ConcurrentWorker::Group::Task"
            end

            missing << "Async::Pool::Controller.wrap" unless ::Async::Pool::Controller.respond_to?(:wrap)
            CONTROLLER_METHODS.each do |method|
              missing << "Async::Pool::Controller##{method}" unless ::Async::Pool::Controller.method_defined?(method)
            end
            # Connections::Controller overrides it to leave the gardener out.
            missing << "Async::Pool::Controller#start_gardener" unless ::Async::Pool::Controller.protected_method_defined?(:start_gardener)

            return if missing.empty?

            raise IncompatibleError, "redis-async-pool doesn't support these versions of its dependencies (missing: #{missing.join(", ")})"
          end

          private

          def keywords?(method, *names)
            accepted = method.parameters.filter_map { |kind, name| name if [:key, :keyreq].include?(kind) }
            (names - accepted).empty?
          end
        end
      end
    end
  end
end
