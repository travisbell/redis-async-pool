# frozen_string_literal: true

RSpec.describe("Sets") do
  conform "sadd, srem, smembers, sismember, smismember and scard" do |r|
    [
      r.sadd("s", "a"), r.sadd("s", ["b", "c"]), r.sadd?("s", "a"), r.sadd?("s", "d"),
      r.srem("s", "d"), r.srem("s", ["c", "z"]), r.srem?("s", "z"), r.srem?("s", "b"),
      r.smembers("s"), r.sismember("s", "a"), r.sismember("s", "z"), r.smismember("s", "a", "z"), r.smismember("s", ["a"]),
      r.scard("s"), r.smembers("missing")
    ]
  end

  conform "spop, srandmember and smove" do |r|
    [
      r.sadd("{s}a", "x"), r.srandmember("{s}a"), r.srandmember("{s}a", 2), r.smove("{s}a", "{s}b", "x"), r.smove("{s}a", "{s}b", "x"),
      r.spop("{s}b"), r.spop("{s}b"), r.sadd("{s}b", ["y"]), r.spop("{s}b", 1)
    ]
  end

  conform "sdiff, sinter and sunion, and their store variants" do |r|
    [
      r.sadd("{s}a", ["1", "2", "3"]), r.sadd("{s}b", ["2", "3", "4"]),
      r.sdiff("{s}a", "{s}b"), r.sinter("{s}a", "{s}b"), r.sunion("{s}a", "{s}b"),
      r.sdiffstore("{s}d", "{s}a", "{s}b"), r.sinterstore("{s}i", ["{s}a", "{s}b"]), r.sunionstore("{s}u", "{s}a", "{s}b"),
      r.smembers("{s}d"), r.smembers("{s}i"), r.smembers("{s}u")
    ]
  end

  conform "set operations across slots" do |r|
    [r.sadd("a", "1"), r.sadd("b", "1"), r.sinter("a", "b")]
  end

  conform "sscan" do |r|
    [r.sadd("s", ["a", "b"]), r.sscan("s", 0), r.sscan("s", 0, match: "a*")]
  end

  conform "sscan_each", modes: [:direct] do |r|
    r.sadd("s", ["a", "b"])
    r.sscan_each("s").to_a
  end
end
