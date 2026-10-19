# frozen_string_literal: true

# Compares redis-async-pool with redis-rb as code written for threads pools it (a ConnectionPool::Wrapper of
# clients), under Async as Falcon runs them: each measurement runs N fibers in one reactor, closed-loop,
# against the disposable servers from docker-compose.yml. See bench/README.md.
#
#   bundle exec ruby bench/run.rb
#   bundle exec ruby bench/run.rb --quick
#   bundle exec ruby bench/run.rb --targets standalone --scenarios get,fanout --concurrency 1,64 --pools 4

Warning[:experimental] = false
RubyVM::YJIT.enable if defined?(RubyVM::YJIT) && !RubyVM::YJIT.enabled?

require "async"
require "async/barrier"
require "connection_pool"
require "etc"
require "json"
require "optparse"
require "time"

require_relative "../lib/redis/async/pool"

module Bench
  STANDALONE_URL = ENV.fetch("REDIS_URL", "redis://localhost:6390")
  CLUSTER_URL = ENV.fetch("REDIS_CLUSTER_URL", "redis://localhost:6391")
  REMOTE_PORT = 6490

  KEYS = Array.new(1_000) { |i| "bench:#{i}" }
  VALUE = "x" * 100
  HASH = "bench:hash"
  FIELDS = Array.new(20) { |i| ["field#{i}", "value#{i}"] }.flatten

  # What each scenario does per operation, for each kind of client.
  SCENARIOS = {
    "get" => "GET of a 100-byte value",
    "set" => "SET of a 100-byte value",
    "hgetall" => "HGETALL of a 20-field hash",
    "pipeline" => "a pipeline of 10 GETs",
    "mget" => "MGET of 10 keys (split across nodes on the cluster)",
    "fanout" => "5 GETs from 5 fibers at once"
  }.freeze

  # A client under test: how to build it, and how it runs each scenario.
  Subject = Struct.new(:name, :label, :targets, :build, :scenarios, keyword_init: true)

  REDIS_RB = {
    "get" => ->(r, keys) { r.get(keys[0]) },
    "set" => ->(r, keys) { r.set(keys[0], VALUE) },
    "hgetall" => ->(r, _) { r.hgetall(HASH) },
    "pipeline" => ->(r, keys) { r.pipelined { |p| keys.each { |key| p.get(key) } } },
    "mget" => ->(r, keys) { r.mget(*keys) },
    "fanout" => lambda do |r, keys|
      barrier = Async::Barrier.new
      keys.first(5).each { |key| barrier.async { r.get(key) } }
      barrier.wait
    end
  }.freeze

  SUBJECTS = [
    Subject.new(
      name: "redis-rb",
      label: "redis-rb in a ConnectionPool::Wrapper (a client per checkout)",
      targets: [:standalone, :remote, :cluster],
      scenarios: REDIS_RB,
      build: lambda do |target, url, size|
        ConnectionPool::Wrapper.new(size: size, timeout: 30) do
          target == :cluster ? Redis::Cluster.new(nodes: [url]) : Redis.new(url: url)
        end
      end
    ),
    Subject.new(
      name: "async-pool",
      label: "redis-async-pool over async-pool (with fiber fan-out on the cluster)",
      targets: [:standalone, :remote, :cluster],
      scenarios: REDIS_RB,
      build: lambda do |target, url, size|
        pool = { size: size, timeout: 30 }
        target == :cluster ? Redis::Async::Pool::ClusterClient.new(nodes: [url], pool: pool) : Redis::Async::Pool::Client.new(url: url, pool: pool)
      end
    ),
    Subject.new(
      name: "connection_pool",
      label: "redis-async-pool over connection_pool",
      targets: [:standalone, :remote, :cluster],
      scenarios: REDIS_RB,
      build: lambda do |target, url, size|
        pool = { size: size, timeout: 30, async: false }
        target == :cluster ? Redis::Async::Pool::ClusterClient.new(nodes: [url], pool: pool) : Redis::Async::Pool::Client.new(url: url, pool: pool)
      end
    )
  ].freeze

  class Runner
    DEFAULTS = {
      targets: [:standalone, :remote, :cluster],
      scenarios: SCENARIOS.keys,
      concurrency: [1, 16, 64, 256],
      pools: [4, 32],
      subjects: SUBJECTS.map(&:name),
      duration: 5.0,
      warmup: 1.0,
      latency_ms: 1.0
    }.freeze

    def initialize(options)
      @options = DEFAULTS.merge(options)
      @results = []
    end

    def run
      seed
      proxy = start_proxy if @options[:targets].include?(:remote)
      puts header
      watchdog = start_watchdog

      @options[:targets].each do |target|
        subjects = SUBJECTS.select { |subject| @options[:subjects].include?(subject.name) && subject.targets.include?(target) }
        @options[:scenarios].each do |scenario|
          @options[:pools].each do |pool|
            @options[:concurrency].each do |concurrency|
              subjects.each do |subject|
                @step = "#{target} #{scenario} #{subject.name} pool #{pool} fibers #{concurrency}"
                @progressed_at = monotonic
                measure(subject, target, scenario, pool, concurrency)
              end
            end
          end
        end
      end

      save
    ensure
      watchdog&.kill
      stop_proxy(proxy)
      flush
    end

    private

    # If a step makes no progress for --watchdog seconds, prints where every fiber is and exits.
    def start_watchdog
      limit = @options[:watchdog] or return

      Thread.new do
        loop do
          sleep(5)
          next unless @progressed_at && monotonic - @progressed_at > limit

          warn("\nNo progress for #{limit}s in: #{@step}")
          ObjectSpace.each_object(Fiber) do |fiber|
            backtrace = fiber.backtrace rescue nil
            next if backtrace.nil? || backtrace.empty?

            warn("\n#{fiber.inspect}")
            backtrace.reject { |line| line.include?("/rspec") }.first(25).each { |line| warn("  #{line}") }
          end
          exit!(1)
        end
      end
    end

    def url(target)
      case target
      when :standalone then STANDALONE_URL
      when :remote then "redis://localhost:#{REMOTE_PORT}"
      when :cluster then CLUSTER_URL
      end
    end

    def seed
      standalone = Redis.new(url: STANDALONE_URL)
      cluster = Redis::Cluster.new(nodes: [CLUSTER_URL])
      [standalone, cluster].each do |redis|
        KEYS.each_slice(100) { |keys| redis.pipelined { |p| keys.each { |key| p.set(key, VALUE) } } }
        redis.del(HASH)
        redis.hset(HASH, *FIELDS)
      end
    ensure
      standalone&.close
      cluster&.close
    end

    # The servers are the specs' disposable ones, which refuse to run against data.
    def flush
      Redis.new(url: STANDALONE_URL).tap(&:flushall).close
      Redis::Cluster.new(nodes: [CLUSTER_URL]).tap(&:flushall).close
    end

    def measure(subject, target, scenario, pool, concurrency)
      operation = subject.scenarios.fetch(scenario)
      latencies = []
      errors = 0
      operations = 0
      client = nil

      Sync do
        client = subject.build.call(target, url(target), pool)
        check!(subject, client, operation, scenario)

        run_for(@options[:warmup], client, operation, concurrency) { nil }
        GC.start

        cpu_before = Process.clock_gettime(Process::CLOCK_PROCESS_CPUTIME_ID)
        started = monotonic
        run_for(@options[:duration], client, operation, concurrency) do |latency, error|
          operations += 1
          error ? errors += 1 : latencies << latency
        end
        elapsed = monotonic - started
        cpu = Process.clock_gettime(Process::CLOCK_PROCESS_CPUTIME_ID) - cpu_before

        latencies.sort!
        result = {
          subject: subject.name, target: target, scenario: scenario, pool: pool, concurrency: concurrency,
          ops_per_second: (operations / elapsed).round(1), errors: errors,
          p50_ms: percentile(latencies, 0.50), p90_ms: percentile(latencies, 0.90), p99_ms: percentile(latencies, 0.99),
          cpu_us_per_op: operations.zero? ? nil : (cpu / operations * 1_000_000).round(1)
        }
        @results << result
        puts row(result)
      ensure
        if client.is_a?(ConnectionPool::Wrapper)
          client.pool_shutdown(&:close)
        else
          client&.close
        end
      end
    end

    # Each scenario must work (and agree with redis-rb) before it's timed.
    def check!(subject, client, operation, scenario)
      reply = operation.call(client, KEYS.first(10))
      expected = case scenario
      when "get" then VALUE
      when "pipeline", "mget" then [VALUE] * 10
      when "hgetall" then FIELDS.each_slice(2).to_h
      end
      raise "#{subject.name} #{scenario} returned #{reply.inspect[0, 200]}" if expected && reply != expected
    end

    # Runs the operation from concurrency fibers until the duration ends, yielding each one's latency.
    def run_for(duration, client, operation, concurrency)
      deadline = monotonic + duration
      barrier = Async::Barrier.new

      concurrency.times do |fiber|
        barrier.async do
          offset = (fiber * 10) % (KEYS.size - 10)
          keys = KEYS[offset, 10]

          while monotonic < deadline
            started = monotonic
            begin
              operation.call(client, keys)
              yield((monotonic - started) * 1000, false)
            rescue StandardError => error
              warn("#{error.class}: #{error.message}") if $VERBOSE
              yield(nil, true)
            end
          end
        end
      end

      barrier.wait
    end

    def percentile(sorted, fraction)
      return if sorted.empty?

      sorted[(fraction * (sorted.size - 1)).round].round(3)
    end

    def monotonic
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def start_proxy
      pid = spawn(RbConfig.ruby, File.join(__dir__, "latency_proxy.rb"), REMOTE_PORT.to_s, STANDALONE_URL.delete_prefix("redis://"), @options[:latency_ms].to_s, out: File::NULL)
      30.times do
        TCPSocket.new("localhost", REMOTE_PORT).close
        return pid
      rescue SystemCallError
        sleep(0.1)
      end
      raise "The latency proxy didn't start"
    end

    def stop_proxy(pid)
      return unless pid

      Process.kill("TERM", pid)
      Process.wait(pid)
    rescue Errno::ESRCH, Errno::ECHILD
      nil
    end

    def header
      lines = [
        "Ruby #{RUBY_VERSION}#{" +YJIT" if defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled?}, #{Etc.nprocessors} CPUs; redis-rb #{Redis::VERSION}, redis-client #{RedisClient::VERSION}, redis-async-pool #{Redis::Async::Pool::VERSION}",
        "#{@options[:duration]}s per measurement after #{@options[:warmup]}s warmup; remote adds #{@options[:latency_ms]}ms per round trip",
        "",
        format("%-11s %-9s %-15s %5s %6s %11s %7s %8s %8s %8s %6s", "target", "scenario", "subject", "pool", "fibers", "ops/s", "errors", "p50 ms", "p90 ms", "p99 ms", "cpu µs")
      ]
      lines.join("\n")
    end

    def row(result)
      format(
        "%-11s %-9s %-15s %5d %6d %11.1f %7d %8s %8s %8s %6s",
        result[:target], result[:scenario], result[:subject], result[:pool], result[:concurrency], result[:ops_per_second], result[:errors],
        result[:p50_ms], result[:p90_ms], result[:p99_ms], result[:cpu_us_per_op]
      )
    end

    def save
      path = File.join(__dir__, "results", "#{Time.now.strftime("%Y%m%d-%H%M%S")}.json")
      environment = { ruby: RUBY_VERSION, yjit: defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled?, cpus: Etc.nprocessors, redis_rb: Redis::VERSION, redis_client: RedisClient::VERSION, redis_async_pool: Redis::Async::Pool::VERSION, options: @options }
      File.write(path, JSON.pretty_generate(environment: environment, results: @results))
      puts "\nResults: #{path}"
    end
  end
end

if $PROGRAM_NAME == __FILE__
  options = {}

  OptionParser.new do |parser|
    parser.on("--quick", "2s measurements, 0.5s warmup") do
      options[:duration] = 2.0
      options[:warmup] = 0.5
    end
    parser.on("--targets LIST", Array, "standalone,remote,cluster") { |value| options[:targets] = value.map(&:to_sym) }
    parser.on("--scenarios LIST", Array, Bench::SCENARIOS.keys.join(",")) { |value| options[:scenarios] = value }
    parser.on("--subjects LIST", Array, Bench::SUBJECTS.map(&:name).join(",")) { |value| options[:subjects] = value }
    parser.on("--concurrency LIST", Array, "fibers, e.g. 1,16,64,256") { |value| options[:concurrency] = value.map { |v| Integer(v) } }
    parser.on("--pools LIST", Array, "connections per pool, e.g. 4,32") { |value| options[:pools] = value.map { |v| Integer(v) } }
    parser.on("--duration SECONDS", Float) { |value| options[:duration] = value }
    parser.on("--latency-ms MS", Float, "added per round trip for the remote target") { |value| options[:latency_ms] = value }
    parser.on("--watchdog SECONDS", Float, "print every fiber's backtrace and exit if a step stalls this long") { |value| options[:watchdog] = value }
  end.parse!

  Bench::Runner.new(options).run
end
