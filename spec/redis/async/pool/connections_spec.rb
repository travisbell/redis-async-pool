# frozen_string_literal: true

RSpec.describe(Redis::Async::Pool::Connections) do
  let(:config) { RedisClient.config(url: Conformance::URLS[:standalone]) }
  let(:pool) { described_class.new(size: 2, server_url: config.server_url, timeout: 0.5) { config.new_client } }

  after { pool.shutdown }

  it "gives a fiber that already holds a connection the same one, as connection_pool does" do
    Sync do
      pool.with do |outer|
        pool.with { |inner| expect(inner).to(equal(outer)) }
      end
    end
  end

  it "gives the fibers a fiber starts connections of their own" do
    Sync do
      pool.with do |outer|
        child = Async { pool.with { |inner| inner } }.wait
        expect(child).not_to(equal(outer))
      end
    end
  end

  it "raises ConnectionPool::TimeoutError when no connection is free in time" do
    Sync do
      pool.with do
        Async do
          pool.with do
            expect { Async { pool.with { nil } }.wait }.to(raise_error(ConnectionPool::TimeoutError))
          end
        end.wait
      end
    end
  end

  it "tags the pool with the server's URL" do
    expect(pool.controller.tags).to(include(endpoint: config.server_url))
  end
end
