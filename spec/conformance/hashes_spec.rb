# frozen_string_literal: true

RSpec.describe("Hashes") do
  conform "hset, hget, hgetall, hkeys, hvals, hlen, hexists and hdel" do |r|
    [
      r.hset("h", "a", "1", "b", "2"), r.hset("h", { "c" => "3" }), r.hget("h", "a"), r.hget("h", "z"),
      r.hgetall("h"), r.hkeys("h"), r.hvals("h"), r.hlen("h"), r.hexists("h", "a"), r.hexists("h", "z"),
      r.hdel("h", "a", "b"), r.hdel("h", ["c"]), r.hgetall("h"), r.hkeys("missing")
    ]
  end

  conform "hsetnx, hmset, hmget, mapped_hmset and mapped_hmget" do |r|
    [
      r.hsetnx("h", "a", "1"), r.hsetnx("h", "a", "2"), r.hmset("h", "b", "2", "c", "3"),
      r.hmget("h", "a", "b", "z"), r.hmget("h", ["a", "b"]),
      r.mapped_hmset("m", { "x" => "1" }), r.mapped_hmget("m", "x", "y")
    ]
  end

  conform "hincrby and hincrbyfloat" do |r|
    [r.hincrby("h", "n", 5), r.hincrby("h", "n", -2), r.hincrbyfloat("h", "f", 1.5), r.hincrbyfloat("h", "f", 0.25)]
  end

  conform "hrandfield" do |r|
    [r.hset("h", "a", "1"), r.hrandfield("h"), r.hrandfield("h", 1), r.hrandfield("h", 1, with_values: true), r.hrandfield("missing")]
  end

  conform "hscan" do |r|
    [r.hset("h", "a", "1", "b", "2"), r.hscan("h", 0), r.hscan("h", 0, match: "a*", count: 10)]
  end

  conform "hscan_each", modes: [:direct] do |r|
    r.hset("h", "a", "1", "b", "2")
    [r.hscan_each("h").to_a, r.hscan_each("h", match: "b*").to_a]
  end

  conform "hstrlen (sent through method_missing by redis-rb)" do |r|
    # covers: method_missing
    [r.hset("h", "a", "abc"), r.hstrlen("h", "a")]
  end
end
