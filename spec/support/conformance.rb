# frozen_string_literal: true

require "redis-clustering"
require "timeout"
require "yaml"

# Differential testing against redis-rb: each case runs through redis-rb (the reference) and through
# redis-async-pool, each on a freshly flushed server with fresh clients, and must return the same values
# and raise the same errors.
module Conformance
  URLS = {
    standalone: ENV.fetch("REDIS_URL", "redis://localhost:6390"),
    cluster: ENV.fetch("REDIS_CLUSTER_URL", "redis://localhost:6391")
  }.freeze

  TARGETS = URLS.keys.freeze
  MODES = [:direct, :pipelined, :multi].freeze
  TIMEOUT = 5

  # Example description => { "gap" => why it fails, "flaky" => whether it only fails on some runs }.
  # CONFORMANCE_GAPS=off runs them as ordinary examples, to see how they fail.
  KNOWN_GAPS = YAML.load_file(File.expand_path("../conformance/known_gaps.yml", __dir__)).each_with_object({}) do |entry, gaps|
    entry.fetch("examples").each { |example| gaps[example] = entry }
  end.then { |gaps| ENV["CONFORMANCE_GAPS"] == "off" ? {} : gaps }.freeze

  # What a case returned or raised. Errors, including those returned inside replies (e.g. by
  # pipelined(exception: false)), are reduced to class and message so they compare by value. An error
  # collected from several cluster nodes is reduced to each node's error instead: its message lists them
  # in the order the nodes replied, which differs between runs.
  Outcome = Data.define(:value, :error) do
    class << self
      def capture
        new(value: normalize(yield), error: nil)
      rescue StandardError, NotImplementedError => error
        new(value: nil, error: describe(error))
      end

      private

      def describe(error)
        if error.is_a?(Redis::Cluster::CommandErrorCollection)
          [error.class.name, error.errors.sort.to_h { |node, node_error| [node, describe(node_error)] }]
        else
          [error.class.name, error.message]
        end
      end

      def normalize(value)
        case value
        when Exception then { error: describe(value) }
        when Array then value.map { |element| normalize(element) }
        when Hash then value.to_h { |key, element| [normalize(key), normalize(element)] }
        else value
        end
      end
    end
  end

  # Defines the cases: `conform(description) { |r| ... }` makes an example for each target and mode.
  module DSL
    # In the :pipelined and :multi modes the block runs inside #pipelined/#multi and the replies are
    # compared; its own return value is ignored.
    #
    # `except` leaves out target/mode pairs (e.g. "cluster/pipelined") where redis-rb's result isn't deterministic.
    #
    # Unless `raises: true`, redis-rb mustn't raise when the case runs directly on a standalone server,
    # so a broken case can't pass by failing the same way on both; with it, redis-rb must raise.
    def conform(description, targets: TARGETS, modes: MODES, except: [], raises: false, &body)
      targets.product(modes).each do |target, mode|
        next if except.include?("#{target}/#{mode}")

        it("#{description} [#{target}/#{mode}]") do
          expected = Conformance.run(:reference, target, mode, body)

          if target == :standalone && mode == :direct
            if raises
              expect(expected.error).not_to(be_nil, "redis-rb didn't raise, but the case says it does")
            else
              expect(expected.error).to(be_nil, "redis-rb raised #{expected.error.inspect}; pass raises: true if that's intended")
            end
          end

          if (gap = KNOWN_GAPS[RSpec.current_example.full_description])
            gap["flaky"] ? skip(gap["gap"]) : pending(gap["gap"])
          end

          expect(Conformance.run(:adapter, target, mode, body)).to(eq(expected))
        end
      end
    end
  end

  @servers = {}
  @claimed = {}

  class << self
    def run(implementation, target, mode, body)
      reset!(target)
      client = public_send(implementation, target)
      @side = side_client = reference(target)

      Outcome.capture do
        if implementation == :adapter
          Sync { Timeout.timeout(TIMEOUT) { execute(client, mode, body) } }
        else
          Timeout.timeout(TIMEOUT) { execute(client, mode, body) }
        end
      end
    ensure
      @side = nil
      [client, side_client].each { |c| c&.close rescue nil }
      servers(target).each(&:flushall)
    end

    def reference(target)
      case target
      when :standalone then Redis.new(url: URLS[target])
      when :cluster then Redis::Cluster.new(nodes: [URLS[target]])
      end
    end

    # The clients under test, over async-pool's pools (or connection_pool's with POOL=connection_pool).
    def adapter(target)
      pool = { size: 5, async: ENV["POOL"] != "connection_pool" }

      case target
      when :standalone then Redis::Async::Pool::Client.new(url: URLS[target], pool: pool)
      when :cluster then Redis::Async::Pool::ClusterClient.new(nodes: [URLS[target]], pool: pool)
      end
    end

    # A redis-rb client on the case's server, for side effects such as publishing to a subscriber.
    def side
      @side or raise "Conformance.side is only available while a case runs"
    end

    # Flushes the target's servers, after checking (once) that they started out empty.
    def reset!(target)
      servers(target).each do |server|
        claim!(server)
        server.flushall
        server.script(:flush)
        server.config(:resetstat)
        sleep(0.01) while persisting?(server)
      end
    end

    # A redis-rb client per server: the standalone server, or every node of the cluster.
    def servers(target)
      @servers[target] ||= case target
      when :standalone
        [Redis.new(url: URLS[target])]
      when :cluster
        seed = Redis.new(url: URLS[target])
        addresses = seed.call("CLUSTER", "NODES").lines.map { |line| line.split[1].split("@").first }
        seed.close
        addresses.map { |address| Redis.new(url: "redis://#{address}") }
      end
    end

    private

    def execute(client, mode, body)
      case mode
      when :direct then body.call(client)
      when :pipelined then client.pipelined { |pipeline| body.call(pipeline) }
      when :multi then client.multi { |transaction| body.call(transaction) }
      end
    end

    # The specs flush the servers between cases, so only servers that start out empty are accepted.
    def claim!(server)
      return if @claimed[server.id]

      keyspace = server.info("keyspace")
      unless keyspace.empty?
        raise "Refusing to flush #{server.id}, which has data (#{keyspace}). The conformance specs need disposable servers: `docker compose up -d`."
      end

      @claimed[server.id] = true
    end

    # Cases may start a background save or AOF rewrite; let it finish so the next case starts clean.
    def persisting?(server)
      persistence = server.info("persistence")
      persistence["rdb_bgsave_in_progress"] == "1" || persistence["aof_rewrite_in_progress"] == "1"
    end
  end
end
