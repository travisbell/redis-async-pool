# frozen_string_literal: true

require "async"
require "async/pool/controller"
require "async/pool/resource"
require "connection_pool"
require "redis"
require "redis-clustering"

require_relative "pool/version"
require_relative "pool/compatibility"

class Redis
  module Async
    # redis-rb's Redis and Redis::Cluster, shared by every fiber, over connection pools.
    module Pool
      class Error < StandardError; end

      # Raised on load when a dependency doesn't have the internals redis-async-pool builds on.
      class IncompatibleError < Error; end

      # The pool: option's defaults: 5 connections (per node, on a cluster), a checkout waiting at most 5 seconds,
      # and async-pool's pools (async: false uses connection_pool's, for threads). tags: label async-pool's pools,
      # e.g. for metrics, alongside the server's URL.
      DEFAULT_POOL = { size: 5, timeout: 5, async: true }.freeze

      class << self
        def pool_options(options)
          DEFAULT_POOL.merge(options || {})
        end
      end
    end
  end
end

Redis::Async::Pool::Compatibility.check!

require_relative "pool/connections"
require_relative "pool/fiber_worker"
require_relative "pool/pooled"
require_relative "pool/client"
require_relative "pool/cluster_client"

# Both only take effect when asked for: pool: { async: true } and concurrency: { model: :async }.
RedisClient::Pooled.prepend(Redis::Async::Pool::AsyncPooled)
RedisClient::Cluster::ConcurrentWorker.singleton_class.prepend(Redis::Async::Pool::ConcurrentWorkerModels)
