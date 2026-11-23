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

  conform "sintercard, sdiffcard and sunioncard" do |r|
    [
      r.sadd("{s}a", ["1", "2", "3", "4"]), r.sadd("{s}b", ["2", "3", "4", "5"]), r.sadd("{s}c", ["3", "4"]),
      r.sintercard("{s}a", "{s}b"), r.sintercard(["{s}a", "{s}b", "{s}c"], limit: 1), r.sintercard("{s}a", "{s}missing"),
      r.sdiffcard("{s}a", "{s}b"), r.sdiffcard("{s}a", "{s}c", limit: 1), r.sdiffcard(["{s}missing", "{s}a"]),
      r.sunioncard("{s}a", "{s}b"), r.sunioncard(["{s}a", "{s}c"], limit: 2), r.sunioncard("{s}a", "{s}b", approx: true),
      r.sunioncard("{s}missing")
    ]
  end

  conform "saddex" do |r|
    at = Time.now.to_i + 1000
    [
      r.saddex("s", "a", "b"), r.sttl("s", "a"), r.saddex("s", ["a", "c"], mnx: true), r.saddex("s", "z", mxx: true),
      r.saddex("s", "a", mxx: true, ex: 100), r.sttl("s", "a"), r.saddex("s", "a", keepttl: true), r.sttl("s", "a"),
      r.saddex("s", "b", px: 200_000), r.spttl("s", "b").map(&:positive?), r.saddex("s", "c", exat: at), r.sexpiretime("s", "c").map { |time| time - at },
      r.saddex("s", "d", pxat: at * 1000), r.spexpiretime("s", "d").map { |time| time - (at * 1000) }, r.smembers("s").sort
    ]
  end

  conform "saddex with mnx and mxx", raises: true do |r|
    r.saddex("s", "a", mnx: true, mxx: true)
  end

  conform "sexpire, spexpire, sttl, spttl and spersist" do |r|
    [
      r.sadd("s", ["a", "b", "c"]), r.sttl("s", "a"), r.sexpire("s", 100, "a", "z"), r.sttl("s", "a", "b", "z"),
      r.sexpire("s", 50, ["a"], nx: true), r.sexpire("s", 200, "a", gt: true), r.sexpire("s", 300, "a", lt: true), r.sexpire("s", 100, "b", xx: true),
      r.spexpire("s", 100_000, "b"), r.spexpire("s", 1_000, "b", gt: true), r.spexpire("s", 50_000, "b", lt: true),
      r.spttl("s", "a", "b").map(&:positive?), r.spttl("s", "c", "z"), r.spersist("s", "a", "c", "z"), r.spersist("s", ["b"]),
      r.sttl("s", "a", "b"), r.spexpire("s", 1, "c"), r.sttl("missing", "a"), r.spersist("missing", "a")
    ]
  end

  conform "sexpireat, spexpireat, sexpiretime and spexpiretime" do |r|
    at = Time.now.to_i + 1000
    [
      r.sadd("s", ["a", "b", "c"]), r.sexpiretime("s", "a"), r.sexpireat("s", at, "a", "z"),
      r.sexpiretime("s", "a", "b", "z").map { |time| time.positive? ? time - at : time },
      r.spexpireat("s", at * 1000, ["b"], nx: true), r.spexpireat("s", (at + 100) * 1000, "b", gt: true), r.spexpireat("s", (at + 200) * 1000, "b", lt: true),
      r.spexpiretime("s", "b", "c").map { |time| time.positive? ? time - (at * 1000) : time }, r.sexpireat("s", at, "c", xx: true),
      r.sexpireat("s", Time.now.to_i - 10, "c"), r.smembers("s").sort, r.spexpiretime("missing", "a")
    ]
  end
end
