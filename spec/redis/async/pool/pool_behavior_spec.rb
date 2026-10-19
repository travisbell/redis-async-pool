# frozen_string_literal: true

RSpec.describe(Redis::Async::Pool::Client) do
  before { Conformance.reset!(:standalone) }
  after { Conformance.servers(:standalone).each(&:flushall) }

  [true, false].each do |async|
    context "with #{async ? "an async" : "a connection_pool"} pool" do
      def client(**pool)
        @client = described_class.new(url: Conformance::URLS[:standalone], pool: pool.merge(async: @async))
      end

      before { @async = async }
      after { @client&.close }

      it "raises Redis::ConnectionError when no connection is free in time" do
        redis = client(size: 1, timeout: 0.2)

        Sync do
          Async { redis.blpop("never", timeout: 1) }
          sleep(0.05)
          expect { redis.get("k") }.to(raise_error(Redis::ConnectionError, /Couldn't checkout a connection in time: Waited 0.2 sec, 0\/1 available/))
        end
      end

      it "works outside a reactor, and in and out of one" do
        redis = client(size: 2)

        expect([redis.set("k", "1"), redis.get("k"), redis.pipelined { |p| p.incr("k") }]).to(eq(["OK", "1", [2]]))
        expect(Sync { redis.get("k") }).to(eq("2"))
        redis.close
        expect(redis.get("k")).to(eq("2"))
      end

      it "doesn't hide a watch block's error behind a failed UNWATCH, and closes that connection" do
        redis = client(size: 1)
        connection = nil

        expect do
          redis.watch("k") do
            connection = redis.send(:pinned)
            allow(connection).to(receive(:call_v).and_call_original)
            allow(connection).to(receive(:call_v).with(["UNWATCH"]).and_raise(Redis::ConnectionError, "lost"))
            allow(connection).to(receive(:close).and_call_original)
            raise ArgumentError, "the block's own error"
          end
        end.to(raise_error(ArgumentError, "the block's own error"))

        expect(connection).to(have_received(:close).at_least(:once))
        expect(redis.get("k")).to(be_nil)
      end
    end
  end
end
