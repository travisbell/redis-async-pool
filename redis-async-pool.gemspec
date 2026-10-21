# frozen_string_literal: true

require_relative "lib/redis/async/pool/version"

Gem::Specification.new do |spec|
  spec.name = "redis-async-pool"
  spec.version = Redis::Async::Pool::VERSION
  spec.authors = ["Travis Bell"]
  spec.email = ["me@travisbell.com"]

  spec.summary = "redis-rb for Async and Falcon: one client shared by every fiber, over async-pool connection pools."
  spec.description = <<~DESCRIPTION
    redis-rb's Redis and Redis::Cluster serialize every command on one connection, so under Async and
    Falcon each fiber needs a client of its own from a pool. redis-async-pool's clients are redis-rb's own
    Redis and Redis::Cluster, without that serialization, over connection pools (async-pool's, or
    connection_pool's for threads) that every fiber shares; a cluster's commands to several nodes run in
    fibers rather than one after another. Every method, reply and error is redis-rb's.
  DESCRIPTION
  spec.homepage = "https://github.com/travisbell/redis-async-pool"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.4"

  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir["lib/**/*.rb", "README.md", "CHANGELOG.md", "LICENSE.txt"]
  spec.require_paths = ["lib"]

  spec.add_dependency("async", ">= 2.24")
  spec.add_dependency("async-pool", ">= 0.12")
  spec.add_dependency("connection_pool", ">= 2.2")
  # The adapter builds on these gems' internals (see Redis::Async::Pool::Compatibility).
  spec.add_dependency("redis", ">= 5.4")
  spec.add_dependency("redis-client", ">= 0.31")
  spec.add_dependency("redis-cluster-client", ">= 0.17")
  spec.add_dependency("redis-clustering", ">= 5.4")
end
