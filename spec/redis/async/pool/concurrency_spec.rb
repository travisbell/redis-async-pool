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
end
