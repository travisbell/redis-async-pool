# frozen_string_literal: true

require "async/barrier"

# The clients shared by many fibers at once, which the conformance specs (one fiber at a time) don't
# reach: every fiber must get its own replies, and WATCH must stay on its fiber's connection.
RSpec.describe("Clients shared across fibers") do
  {
    "connection_pool" => { async: false },
    "async-pool" => {}
  }.each do |pool_kind, pool_options|
    context "with #{pool_kind}" do
      def concurrently(count = 200)
        Sync do
          barrier = Async::Barrier.new
          results = Array.new(count)
          count.times { |i| barrier.async { results[i] = yield(i) } }
          barrier.wait
          results
        end
      end

      describe Redis::Async::Pool::Client do
        let(:client) { described_class.new(url: Conformance::URLS[:standalone], pool: { size: 8, timeout: 30 }.merge(pool_options)) }

        before { Conformance.reset!(:standalone) }

        after do
          client.close
          Conformance.servers(:standalone).each(&:flushall)
        end

        it "gives every fiber its own replies" do
          results = concurrently do |i|
            client.set("k#{i}", "v#{i}")
            [client.get("k#{i}"), client.pipelined { |p| [p.incr("n#{i}"), p.get("k#{i}")] }, client.multi { |t| t.incr("n#{i}") }]
          end

          expect(results).to(eq(Array.new(200) { |i| ["v#{i}", [1, "v#{i}"], [2]] }))
        end

        it "keeps each watch block's commands on its connection" do
          results = concurrently(50) do |i|
            client.set("w#{i}", "0")
            client.watch("w#{i}") do |c|
              value = c.get("w#{i}")
              c.multi { |t| t.set("w#{i}", Integer(value) + 1) }
            end
          end

          expect(results).to(all(eq(["OK"])))
          expect(Sync { Array.new(50) { |i| client.get("w#{i}") } }).to(all(eq("1")))
        end

        it "aborts a watch block's transaction when another fiber changes the key" do
          result = Sync do
            client.set("w", "0")
            client.watch("w") do |c|
              Async { client.set("w", "changed") }.wait
              c.multi { |t| t.set("w", "mine") }
            end
          end

          expect(result).to(be_nil)
          expect(Sync { client.get("w") }).to(eq("changed"))
        end

        it "doesn't lend a watch block's connection to the fibers it starts" do
          ids = Sync do
            client.watch("w") do |c|
              [c.client(:id), Async { client.client(:id) }.wait]
            end
          end

          expect(ids.uniq.size).to(eq(2))
        end

        it "works again after #close" do
          Sync do
            client.set("k", "1")
            client.close
            expect(client.get("k")).to(eq("1"))
          end
        end
      end

      describe Redis::Async::Pool::ClusterClient do
        let(:client) { described_class.new(nodes: [Conformance::URLS[:cluster]], pool: { size: 8, timeout: 30 }.merge(pool_options)) }

        before { Conformance.reset!(:cluster) }

        after do
          client.close
          Conformance.servers(:cluster).each(&:flushall)
        end

        it "gives every fiber its own replies, across nodes" do
          results = concurrently do |i|
            client.set("a#{i}", "v#{i}")
            client.set("b#{i}", "w#{i}")
            [
              client.mget("a#{i}", "b#{i}"),
              client.pipelined { |p| [p.incr("n#{i}"), p.get("a#{i}"), p.get("b#{i}")] },
              client.multi { |t| [t.incr("{t#{i}}x"), t.incr("{t#{i}}y")] }
            ]
          end

          expect(results).to(eq(Array.new(200) { |i| [["v#{i}", "w#{i}"], [1, "v#{i}", "w#{i}"], [1, 1]] }))
        end

        it "runs watch blocks concurrently" do
          results = concurrently(50) do |i|
            client.set("{w#{i}}k", "0")
            client.watch("{w#{i}}k") do |c|
              value = c.get("{w#{i}}k")
              c.multi { |t| t.set("{w#{i}}k", Integer(value) + 1) }
            end
          end

          expect(results).to(all(eq(["OK"])))
        end

        it "sends commands to every node concurrently" do
          results = concurrently(20) { client.dbsize }

          expect(results).to(all(be_a(Integer)))
        end
      end
    end
  end

  describe "auto-pipelining" do
    # The commands each pipeline and each single call sent, by name, as redis-client's middlewares see them.
    let(:sent) { { pipelines: [], calls: [] } }
    let(:recorder) do
      sent = self.sent
      Module.new do
        define_method(:call) do |command, config, &block|
          sent[:calls] << command.first.downcase
          super(command, config, &block)
        end

        define_method(:call_pipelined) do |commands, config, &block|
          names = commands.map { |command| command.first.downcase }
          sent[:pipelines] << names unless names.include?("hello")
          super(commands, config, &block)
        end
      end
    end

    def client(**pool)
      @client = Redis::Async::Pool::Client.new(url: Conformance::URLS[:standalone], middlewares: [recorder], pool: { size: 1, timeout: 5 }.merge(pool))
    end

    before { Conformance.reset!(:standalone) }

    after do
      @client&.close
      Conformance.servers(:standalone).each(&:flushall)
    end

    it "sends the commands of fibers that find every connection busy in one pipeline" do
      redis = client
      results = Sync do
        barrier = Async::Barrier.new
        tasks = Array.new(20) { |i| barrier.async { redis.set("k#{i}", i.to_s) && redis.get("k#{i}") } }
        barrier.wait
        tasks.map(&:wait)
      end

      expect(results).to(eq(Array.new(20) { |i| i.to_s }))
      expect(sent[:pipelines].map(&:size).max).to(be >= 10)
    end

    it "raises each error, and calls each reply block, in its own fiber" do
      redis = client
      Sync { redis.set("s", "text") }

      outcome = lambda do |redis, i|
        case i % 3
        when 0 then redis.incr("s")
        when 1 then redis.exists?("s")
        else redis.sismember("s", "a")
        end
      rescue Redis::CommandError => error
        [error.class, error.message]
      end

      results = Sync do
        barrier = Async::Barrier.new
        tasks = Array.new(30) { |i| barrier.async { outcome.call(redis, i) } }
        barrier.wait
        tasks.map(&:wait)
      end
      reference = Redis.new(url: Conformance::URLS[:standalone])

      expect(results).to(eq(Array.new(30) { |i| outcome.call(reference, i) }))
      expect(results.map(&:class).uniq).to(contain_exactly(Array, TrueClass))
      expect(sent[:pipelines]).to(include(satisfy { |names| names.size > 1 }))
    ensure
      reference&.close
    end

    it "sends commands that change or block their connection on their own" do
      redis = client
      Sync do
        barrier = Async::Barrier.new
        10.times { barrier.async { redis.call("CLIENT", "ID") } }
        10.times { barrier.async { redis.select(0) } }
        barrier.wait
      end

      expect(sent[:pipelines].flatten & ["client", "select"]).to(be_empty)
      expect(sent[:calls].count("client")).to(eq(10))
    end

    it "raises an invalid argument in its own fiber, as a single command would" do
      redis = client
      results = Sync do
        holder = Async { redis._client.with { sleep(0.02) } }
        sleep(0.01)
        tasks = [Async { redis.set("a", "1") }, Async { redis.get(nil) rescue $! }, Async { redis.get("a") }]
        holder.wait
        tasks.map(&:wait)
      end

      expect(results[0]).to(eq("OK"))
      expect(results[1]).to(be_a(TypeError))
      expect(results[2]).to(eq("1"))
    end

    it "doesn't wake a fiber that was stopped after its reply arrived from what it waits for next" do
      redis = client
      slept = nil
      Sync do
        holder = Async { redis._client.with { sleep(0.02) } }
        sleep(0.01)
        stopped = nil
        stopper = Async do
          redis.get("a")
          stopped.stop
        end
        stopped = Async do
          redis.get("b")
          sleep(1)
        ensure
          started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          sleep(0.2)
          slept = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
        end
        holder.wait
        [stopper, stopped].each(&:wait)
      end

      expect(slept).to(be >= 0.2)
    end

    it "sends each command over a connection of its own with auto_pipeline: false" do
      redis = client(auto_pipeline: false)
      Sync do
        barrier = Async::Barrier.new
        20.times { |i| barrier.async { redis.get("k#{i}") } }
        barrier.wait
      end

      expect(sent[:pipelines]).to(be_empty)
      expect(sent[:calls].count("get")).to(eq(20))
    end

    it "lets the others go on when a waiting fiber, or the one that would send their pipeline, is stopped" do
      redis = client
      results = Sync do
        holder = Async { redis.blpop("never", timeout: 0.2) }
        sleep(0.01)
        leader = Async { redis.get("a") }
        follower = Async { redis.get("b") }
        stopped = Async { redis.get("c") }
        others = Array.new(3) { |i| Async { redis.get("d#{i}") } }
        sleep(0.01)
        leader.stop
        stopped.stop
        holder.wait
        [follower.wait, *others.map(&:wait), redis.set("e", "1"), redis.get("e")]
      end

      expect(results).to(eq([nil, nil, nil, nil, "OK", "1"]))
    end

    it "times out the fibers waiting for a connection when none frees up, each after the pool's timeout" do
      redis = client(timeout: 0.2)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      errors = Sync do
        Async { redis.blpop("never", timeout: 1) }
        sleep(0.01)
        Array.new(5) { Async { redis.get("k") rescue $! } }.map(&:wait)
      end
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

      expect(errors).to(all(be_a(Redis::ConnectionError).and(have_attributes(message: /Couldn't checkout a connection in time/))))
      expect(elapsed).to(be < 1.5)
    end

    it "doesn't fail the others' commands when the fiber that sent their pipeline is stopped or times out" do
      redis = client
      # A script that keeps the server busy for a few tenths of a second, so its pipeline still awaits replies.
      busy = "for i = 1, 200000000 do end return 1"

      [:timeout, :stop].each do |interruption|
        results = Sync do |task|
          holder = Async { redis._client.with { sleep(0.02) } }
          sleep(0.01)
          leader = Async { interruption == :timeout ? task.with_timeout(0.1) { redis.get("a") } : redis.get("a") }
          follower = Async { redis.eval(busy) }
          holder.wait
          if interruption == :stop
            sleep(0.05)
            leader.stop
          end
          [(leader.wait rescue $!), follower.wait]
        end

        expect(results[0]).to(interruption == :timeout ? be_a(Async::TimeoutError) : be_nil)
        expect(results[1]).to(eq(1))
      end
      expect(Sync { redis.set("k", "v") }).to(eq("OK"))
    end
  end

  describe "auto-pipelining on a cluster" do
    # The size of each pipeline sent to a node, as redis-client's middlewares see them.
    let(:sizes) { [] }
    let(:recorder) do
      sizes = self.sizes
      Module.new do
        define_method(:call_pipelined) do |commands, config, &block|
          sizes << commands.size unless commands.any? { |command| command.first.casecmp?("hello") }
          super(commands, config, &block)
        end
      end
    end
    let(:redis) { Redis::Async::Pool::ClusterClient.new(nodes: [Conformance::URLS[:cluster]], middlewares: [recorder], pool: { size: 1, timeout: 5 }) }
    let(:servers) { Conformance.servers(:cluster) }

    before { Conformance.reset!(:cluster) }

    after do
      redis.close
      servers.each(&:flushall)
    end

    def concurrently(count)
      Sync do
        barrier = Async::Barrier.new
        tasks = Array.new(count) { |i| barrier.async { yield(i) } }
        barrier.wait
        tasks.map(&:wait)
      end
    end

    def node_of(slot)
      owner = servers.first.call("CLUSTER", "SLOTS").find { |first, last| (first..last).cover?(slot) }
      servers.find { |server| server.connection[:port] == owner[2][1] }
    end

    # Moves a slot as redis-cli --cluster reshard does: keys: moves only those keys, leaving the slot migrating.
    def move_slot(slot, from, to, keys: nil)
      to_id = to.call("CLUSTER", "MYID")
      to.call("CLUSTER", "SETSLOT", slot, "IMPORTING", from.call("CLUSTER", "MYID"))
      from.call("CLUSTER", "SETSLOT", slot, "MIGRATING", to_id)
      (keys || from.call("CLUSTER", "GETKEYSINSLOT", slot, 1000)).each do |key|
        from.call("MIGRATE", "127.0.0.1", to.connection[:port], key, 0, 5000)
      end
      return if keys

      [to, from, *(servers - [to, from])].each { |server| server.call("CLUSTER", "SETSLOT", slot, "NODE", to_id) }
    end

    it "sends the nodes' shares of fibers' pipelines and mgets together, giving each fiber its replies" do
      results = concurrently(40) do |i|
        keys = Array.new(6) { |k| "f#{i}:#{k}" }
        redis.mset(*keys.flat_map { |key| [key, "#{key}!"] })
        [redis.mget(*keys), redis.pipelined { |p| [p.get(keys[0]), p.incr("n#{i}"), p.get(keys[5])] }, redis.del(*keys)]
      end

      expect(results).to(eq(Array.new(40) { |i| [Array.new(6) { |k| "f#{i}:#{k}!" }, ["f#{i}:0!", 1, "f#{i}:5!"], 6] }))
      expect(sizes.max).to(be > 6)
    end

    it "raises or returns a pipeline's errors as redis-rb does" do
      outcome = lambda do |client, i|
        client.pipelined(exception: i.even?) { |p| [p.set("s#{i}", "x"), p.incr("s#{i}"), p.get("t#{i}"), p.incr("u#{i}")] }
          .map { |reply| reply.is_a?(StandardError) ? [reply.class, reply.message] : reply }
      rescue Redis::BaseError => error
        [error.class, error.message.gsub(/127\.0\.0\.1:\d+/, "node")]
      end

      results = concurrently(20) { |i| outcome.call(redis, i) }
      servers.each(&:flushall)
      reference = Redis::Cluster.new(nodes: [Conformance::URLS[:cluster]])

      expect(results).to(eq(Array.new(20) { |i| outcome.call(reference, i) }))
      expect(sizes.max).to(be > 4)
    ensure
      reference&.close
    end

    it "follows MOVED and ASK redirections in the nodes' shares" do
      slot = servers.first.call("CLUSTER", "KEYSLOT", "{m}")
      from = node_of(slot)
      to = (servers - [from]).first
      read = ->(i) { redis.mget("o#{i}", "{m}a", "{m}b") }

      Sync { [redis.mset("{m}a", "1", "{m}b", "2"), (0...30).map { |i| redis.set("o#{i}", i.to_s) }] }

      # The client's slot map is now stale: the slot's node answers MOVED.
      move_slot(slot, from, to)
      expect(concurrently(30) { |i| read.call(i) }).to(eq(Array.new(30) { |i| [i.to_s, "1", "2"] }))

      # Halfway through moving it back, the slot's node answers ASK for the key that has moved.
      move_slot(slot, to, from, keys: ["{m}a"])
      expect(concurrently(30) { |i| read.call(i) }).to(eq(Array.new(30) { |i| [i.to_s, "1", "2"] }))
      expect(sizes.max).to(be > 3)
    ensure
      move_slot(slot, to, from) if to
    end
  end
end
