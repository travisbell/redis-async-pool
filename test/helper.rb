# frozen_string_literal: true

# redis-rb's own lint tests (vendored from redis-rb's test/lint), run against redis-async-pool's Client: the
# replies redis-rb's maintainers expect, where the conformance specs compare with redis-rb's.
#
#   bundle exec rake lint                        # over async-pool
#   POOL=connection_pool bundle exec rake lint   # over connection_pool

require "minitest/autorun"
require "redis/async/pool"

module LintHelper
  URL = ENV.fetch("REDIS_URL", "redis://localhost:6390")
  DB = 15

  def setup
    @redis = Redis::Async::Pool::Client.new(url: URL, db: DB, pool: { async: ENV["POOL"] != "connection_pool" })
    @redis.flushdb
  end

  def teardown
    @redis&.flushdb
    @redis&.close
  rescue StandardError
    nil
  end

  def r
    @redis
  end

  def redis
    @redis
  end

  def redis_mock(_commands, _options = {})
    skip "redis_mock is redis-rb's fake server, which these tests don't use"
  end

  def target_version(version)
    if Gem::Version.new(redis_server_version) >= Gem::Version.new(version)
      yield
    else
      skip "Requires Redis #{version}+"
    end
  end

  def assert_in_range(range, value)
    assert range.include?(value), "Expected #{value} to be in #{range}"
  end

  # SELECT would switch only one of the pool's connections.
  def with_db(_db)
    skip "SELECT applies to one pooled connection"
  end

  private

  def redis_server_version
    @redis_server_version ||= r.info("server")["redis_version"]
  end
end
