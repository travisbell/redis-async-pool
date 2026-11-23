# frozen_string_literal: true

RSpec.describe("Sorted sets") do
  conform "zadd and its options" do |r|
    [
      r.zadd("z", 1, "a"), r.zadd("z", 1, "a"), r.zadd("z", [[2, "b"], [3, "c"]]), r.zadd("z", [4, "d"]),
      r.zadd("z", 5, "a", xx: true), r.zadd("z", 6, "e", xx: true), r.zadd("z", 7, "a", nx: true),
      r.zadd("z", 1, "a", gt: true, ch: true), r.zadd("z", 1, "a", lt: true, ch: true), r.zadd("z", 2.5, "a", incr: true),
      r.zadd("z", 1, "missing", xx: true, incr: true), r.zrange("z", 0, -1, with_scores: true)
    ]
  end

  conform "zcard, zscore, zmscore, zincrby, zcount and zlexcount" do |r|
    [
      r.zadd("z", [[1, "a"], [2.5, "b"], [3, "c"]]), r.zcard("z"), r.zscore("z", "b"), r.zscore("z", "z"), r.zmscore("z", "a", "z"),
      r.zincrby("z", 1.5, "a"), r.zcount("z", 2, "+inf"), r.zcount("z", "(2.5", 3), r.zlexcount("z", "-", "+"),
      r.zadd("inf", "+inf", "x"), r.zscore("inf", "x"), r.zadd("inf", "-inf", "y"), r.zrange("inf", 0, -1, with_scores: true)
    ]
  end

  conform "zrange and its options" do |r|
    [
      r.zadd("z", [[1, "a"], [2, "b"], [3, "c"], [4, "d"]]),
      r.zrange("z", 0, 1), r.zrange("z", 0, -1, withscores: true), r.zrange("z", 2, 3, by_score: true),
      r.zrange("z", "(1", "+inf", by_score: true, limit: [1, 2], with_scores: true), r.zrange("z", 0, 1, rev: true),
      r.zrange("z", "[a", "[c", by_lex: true), r.zrange("z", "+", "-", by_lex: true, rev: true, limit: [0, 2]),
      r.zrevrange("z", 0, 1), r.zrevrange("z", 0, 1, with_scores: true)
    ]
  end

  conform "zrangebyscore, zrevrangebyscore, zrangebylex and zrevrangebylex" do |r|
    [
      r.zadd("z", [[1, "a"], [2, "b"], [3, "c"]]),
      r.zrangebyscore("z", 1, 2), r.zrangebyscore("z", "-inf", "+inf", with_scores: true, limit: [1, 1]),
      r.zrevrangebyscore("z", "+inf", 2), r.zrevrangebyscore("z", 3, 1, withscores: true),
      r.zrangebylex("z", "[a", "(c"), r.zrangebylex("z", "-", "+", limit: [0, 1]), r.zrevrangebylex("z", "+", "[b")
    ]
  end

  conform "zrank and zrevrank" do |r|
    [r.zadd("z", [[1, "a"], [2, "b"]]), r.zrank("z", "b"), r.zrank("z", "b", with_score: true), r.zrevrank("z", "b"), r.zrevrank("z", "a", withscore: true), r.zrank("z", "z")]
  end

  conform "zrem, zremrangebyrank and zremrangebyscore" do |r|
    [
      r.zadd("z", [[1, "a"], [2, "b"], [3, "c"], [4, "d"], [5, "e"]]), r.zrem("z", "a"), r.zrem("z", ["b", "z"]),
      r.zremrangebyrank("z", 0, 0), r.zremrangebyscore("z", 5, "+inf"), r.zrange("z", 0, -1)
    ]
  end

  conform "zpopmax, zpopmin, bzpopmax and bzpopmin" do |r|
    [
      r.zadd("{z}a", [[1, "a"], [2, "b"], [3, "c"], [4, "d"]]), r.zpopmax("{z}a"), r.zpopmin("{z}a"), r.zpopmax("{z}a", 1), r.zpopmin("{z}a", 5),
      r.zpopmax("{z}a"), r.zadd("{z}a", [[1, "a"], [2, "b"]]), r.bzpopmax("{z}a", timeout: 0.1), r.bzpopmin("{z}missing", "{z}a", timeout: 0.1),
      r.bzpopmin("{z}a", timeout: 0.1)
    ]
  end

  # As with BLMPOP (see Lists), redis-rb's cluster pipelines run ZMPOP and BZMPOP out of order. See "Cluster pipelines".
  conform "zmpop and bzmpop", except: ["cluster/pipelined"] do |r|
    [
      r.zadd("{z}a", [[1, "a"], [2, "b"], [3, "c"]]), r.zmpop("{z}missing", "{z}a"), r.zmpop("{z}a", modifier: "MAX", count: 5), r.zmpop("{z}a"),
      r.zadd("{z}a", [[1, "a"], [2, "b"]]), r.bzmpop(0.1, "{z}a"), r.bzmpop(0.1, "{z}a", modifier: "MAX", count: 2), r.bzmpop(0.1, "{z}a")
    ]
  end

  conform "zrandmember" do |r|
    [r.zadd("z", 1.5, "a"), r.zrandmember("z"), r.zrandmember("z", 1), r.zrandmember("z", 1, with_scores: true), r.zrandmember("missing")]
  end

  conform "zinter, zunion and zdiff, and their store variants" do |r|
    [
      r.zadd("{z}a", [[1, "x"], [2, "y"]]), r.zadd("{z}b", [[10, "y"], [20, "z"]]),
      r.zinter("{z}a", "{z}b"), r.zinter("{z}a", "{z}b", weights: [2, 1], aggregate: "max", with_scores: true),
      r.zunion("{z}a", "{z}b"), r.zunion("{z}a", "{z}b", with_scores: true, aggregate: "min"),
      r.zdiff("{z}a", "{z}b"), r.zdiff("{z}a", "{z}b", with_scores: true),
      r.zinterstore("{z}i", ["{z}a", "{z}b"], weights: [1, 2]), r.zunionstore("{z}u", ["{z}a", "{z}b"], aggregate: "sum"), r.zdiffstore("{z}d", ["{z}a", "{z}b"]),
      r.zrange("{z}i", 0, -1, with_scores: true), r.zrange("{z}u", 0, -1, with_scores: true), r.zrange("{z}d", 0, -1, with_scores: true)
    ]
  end

  conform "zrangestore" do |r|
    [r.zadd("{z}a", [[1, "a"], [2, "b"], [3, "c"]]), r.zrangestore("{z}d", "{z}a", 0, 1), r.zrangestore("{z}e", "{z}a", 2, 3, by_score: true), r.zrange("{z}e", 0, -1)]
  end

  conform "zscan" do |r|
    [r.zadd("z", [[1, "a"], [2.5, "b"]]), r.zscan("z", 0), r.zscan("z", 0, match: "a*", count: 10)]
  end

  conform "zscan_each", modes: [:direct] do |r|
    r.zadd("z", [[1, "a"], [2.5, "b"]])
    r.zscan_each("z").to_a
  end

  conform "zmove" do |r|
    [
      r.zadd("{z}a", [[1, "a"], [2, "b"], [3, "c"], [4, "d"], [5, "e"], [6, "f"]]), r.zmove("{z}a", "{z}b"),
      r.zmove("{z}a", "{z}b", modifier: "MAX", count: 2), r.zmove("{z}a", "{z}b", byscore: ["(2", 4]),
      r.zmove("{z}a", "{z}b", byscore: [10, "+inf"]), r.zmove("{z}missing", "{z}b"), r.zrange("{z}a", 0, -1, with_scores: true),
      r.zrange("{z}b", 0, -1, with_scores: true)
    ]
  end

  conform "zmove with modifier and byscore", raises: true do |r|
    r.zmove("{z}a", "{z}b", modifier: "MAX", byscore: [1, 2])
  end

  conform "zmovemember" do |r|
    [
      r.zadd("{z}a", [[1, "a"], [2, "b"], [3, "c"], [4, "d"]]), r.zadd("{z}b", 10, "c"), r.zmovemember("{z}a", "{z}b", "a"),
      r.zmovemember("{z}a", "{z}b", ["b", "z", "b"]), r.zmovemember("{z}a", "{z}b", ["c", "d"], nx: true),
      r.zmovemember("{z}a", "{z}b", "c", xx: true), r.zmovemember("{z}a", "{z}b", "z"), r.zrange("{z}a", 0, -1, with_scores: true),
      r.zrange("{z}b", 0, -1, with_scores: true)
    ]
  end

  conform "bzmove" do |r|
    [
      r.zadd("{z}a", [[1, "a"], [2, "b"], [3, "c"]]), r.bzmove("{z}a", "{z}b", timeout: 0.1), r.bzmove("{z}a", "{z}b", timeout: 0.1, modifier: "MAX", count: 5),
      r.bzmove("{z}a", "{z}b", timeout: 0.1), r.zrange("{z}b", 0, -1, with_scores: true)
    ]
  end

  conform "zintercard" do |r|
    [
      r.zadd("{z}a", [[1, "x"], [2, "y"], [3, "z"]]), r.zadd("{z}b", [[1, "y"], [2, "z"]]), r.zintercard("{z}a", "{z}b"),
      r.zintercard(["{z}a", "{z}b"], limit: 1), r.zintercard("{z}a", "{z}missing")
    ]
  end

  conform "zunion, zinter and their store variants with aggregate count" do |r|
    [
      r.zadd("{z}a", [[1, "x"], [2, "y"]]), r.zadd("{z}b", [[10, "y"], [20, "z"]]), r.zadd("{z}c", [[5, "y"]]),
      r.zunion("{z}a", "{z}b", "{z}c", aggregate: "count", with_scores: true), r.zinter("{z}a", "{z}b", aggregate: "COUNT", with_scores: true),
      r.zunion("{z}a", "{z}b", weights: [2, 3], aggregate: "count", with_scores: true),
      r.zunionstore("{z}u", ["{z}a", "{z}b", "{z}c"], aggregate: "count"), r.zinterstore("{z}i", ["{z}b", "{z}c"], aggregate: "count"),
      r.zrange("{z}u", 0, -1, with_scores: true), r.zrange("{z}i", 0, -1, with_scores: true)
    ]
  end

  conform "zrank and zrevrank with_score of a missing member" do |r|
    [r.zadd("z", 1, "a"), r.zrank("z", "z", with_score: true), r.zrevrank("z", "z", withscore: true), r.zrank("missing", "a", with_score: true)]
  end
end
