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

  conform "hexpire, hpexpire, httl and hpttl" do |r|
    [
      r.hset("h", "a", "1", "b", "2"), r.httl("h", "a"), r.hexpire("h", 100, "a", "z"), r.httl("h", "a", "b", "z"),
      r.hpexpire("h", 200_000, "b"), r.hpexpire("h", 1, "b", nx: true), r.httl("h", "b"),
      r.hpttl("h", "a", "b").map(&:positive?), r.hpttl("h", "z"), r.httl("missing", "a")
    ]
  end

  conform "hexpire and hpexpire conditions" do |r|
    [
      r.hset("h", "a", "1", "b", "2"), r.hexpire("h", 100, "a", xx: true), r.hexpire("h", 100, "a", nx: true), r.hexpire("h", 50, "a", nx: true),
      r.hexpire("h", 200, "a", gt: true), r.hexpire("h", 300, "a", lt: true), r.hexpire("h", 50, "a", lt: true), r.httl("h", "a"),
      r.hpexpire("h", 100_000, ["b"], xx: true), r.hpexpire("h", 100_000, "b", "z", nx: true), r.hpexpire("h", 1_000, "b", gt: true),
      r.hpexpire("h", 500_000, "b", lt: true), r.httl("h", "b")
    ]
  end

  conform "hexpire with more than one condition", raises: true do |r|
    r.hexpire("h", 100, "a", nx: true, xx: true)
  end

  conform "hexpireat, hpexpireat, hexpiretime, hpexpiretime and hpersist" do |r|
    at = Time.now.to_i + 1000
    [
      r.hset("h", "a", "1", "b", "2", "c", "3"), r.hexpiretime("h", "a"), r.hexpireat("h", at, "a", "z"),
      r.hexpiretime("h", "a", "b", "z").map { |time| time.positive? ? time - at : time },
      r.hpexpireat("h", at * 1000, ["b"], nx: true), r.hpexpireat("h", (at + 100) * 1000, "b", gt: true),
      r.hpexpireat("h", (at + 200) * 1000, "b", lt: true), r.hpexpiretime("h", "b", "c").map { |time| time.positive? ? time - (at * 1000) : time },
      r.hexpireat("h", at, "c", xx: true), r.hpersist("h", "a", "c", "z"), r.hpersist("h", ["b"]), r.httl("h", "a", "b"),
      r.hexpireat("h", Time.now.to_i - 10, "c"), r.hgetall("h"), r.hexpiretime("missing", "a"), r.hpersist("missing", "a")
    ]
  end

  conform "hgetdel" do |r|
    [
      r.hset("h", "a", "1", "b", "2", "c", "3"), r.hgetdel("h", "a", "z"), r.hgetdel("h", ["b"]), r.hgetall("h"),
      r.hgetdel("h", "c"), r.exists("h"), r.hgetdel("missing", "a")
    ]
  end

  conform "hgetex" do |r|
    at = Time.now.to_i + 1000
    [
      r.hset("h", "a", "1", "b", "2"), r.hgetex("h", "a", "z"), r.httl("h", "a"), r.hgetex("h", "a", ex: 100), r.httl("h", "a"),
      r.hgetex("h", ["b"], px: 200_000), r.hpttl("h", "b").map(&:positive?), r.hgetex("h", "a", exat: at), r.hexpiretime("h", "a").map { |time| time - at },
      r.hgetex("h", "b", pxat: at * 1000), r.hpexpiretime("h", "b").map { |time| time - (at * 1000) }, r.hgetex("h", "a", "b", persist: true),
      r.httl("h", "a", "b"), r.hgetex("missing", "a", ex: 10)
    ]
  end

  conform "hgetex with more than one expiration", raises: true do |r|
    r.hgetex("h", "a", ex: 10, persist: true)
  end

  conform "hsetex" do |r|
    at = Time.now.to_i + 1000
    [
      r.hsetex("h", "a", "1", "b", "2"), r.httl("h", "a"), r.hsetex("h", { "a" => "x" }, fnx: true), r.hsetex("h", ["c", "3"], fnx: true),
      r.hsetex("h", "z", "0", fxx: true), r.hsetex("h", "a", "x", fxx: true, ex: 100), r.httl("h", "a"),
      r.hsetex("h", "a", "y", keepttl: true), r.httl("h", "a"), r.hsetex("h", "b", "2", px: 200_000), r.hpttl("h", "b").map(&:positive?),
      r.hsetex("h", "c", "3", exat: at), r.hexpiretime("h", "c").map { |time| time - at },
      r.hsetex("h", "c", "4", pxat: at * 1000), r.hpexpiretime("h", "c").map { |time| time - (at * 1000) }, r.hgetall("h")
    ]
  end

  conform "hsetex with fnx and fxx", raises: true do |r|
    r.hsetex("h", "a", "1", fnx: true, fxx: true)
  end

  # HIMPORT fieldsets are server state of the connection that prepared them. redis-rb's cluster pipelines send
  # the keyless HIMPORT PREPARE to a random node, so it may run after the HIMPORT SET. See "Cluster pipelines".
  conform "himport_prepare and himport_set", except: ["cluster/pipelined"] do |r|
    [
      r.himport_prepare("fs", "name", "age"), r.himport_set("{u}1", "fs", "ann", "31"), r.himport_set("{u}2", "fs", ["bob", "42"]),
      r.himport_set("{u}3", "fs", "cy", "7"), r.hgetall("{u}1"), r.hgetall("{u}2"), r.hgetall("{u}3"),
      r.himport_prepare("fs", ["name"]), r.himport_set("{u}1", "fs", "dee"), r.hgetall("{u}1")
    ]
  end

  conform "himport_discard and himport_discard_all", except: ["cluster/pipelined"] do |r|
    [
      r.himport_prepare("a", "f"), r.himport_prepare("b", "f"), r.himport_prepare("c", "f"), r.himport_discard("a"), r.himport_discard("a"),
      r.himport_set("k", "b", "1"), r.himport_discard_all, r.himport_discard_all, r.hgetall("k")
    ]
  end

  conform "himport_set after himport_discard", raises: true do |r|
    [r.himport_prepare("fs", "f"), r.himport_set("k", "fs", "1"), r.himport_discard("fs"), r.himport_set("k", "fs", "2")]
  end

  conform "himport_set after himport_discard_all", raises: true do |r|
    [r.himport_prepare("fs", "f"), r.himport_set("k", "fs", "1"), r.himport_discard_all, r.himport_set("k", "fs", "2")]
  end

  conform "himport_set with an unknown fieldset or the wrong number of values", raises: true, except: ["cluster/pipelined"] do |r|
    [r.himport_prepare("fs", "a", "b"), r.himport_set("k", "fs", "1", "2", "3"), r.himport_set("k", "missing", "1")]
  end
end
