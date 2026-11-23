# frozen_string_literal: true

RSpec.describe("Strings") do
  conform "set and get" do |r|
    [r.set("k", "v"), r.get("k"), r.get("missing")]
  end

  conform "set with options" do |r|
    [
      r.set("k", "v", ex: 100), r.ttl("k"),
      r.set("k", "v", nx: true), r.set("k", "w", xx: true), r.set("missing", "w", xx: true),
      r.set("k", "x", get: true), r.set("k", "y", keepttl: true), r.ttl("k"),
      r.set("e", "v", exat: 4_000_000_000), r.set("p", "v", pxat: 4_000_000_000_000), r.set("q", "v", px: 100_000)
    ]
  end

  conform "setex, psetex and setnx" do |r|
    [r.setex("a", 100, "1"), r.ttl("a"), r.psetex("b", 100_000, "2"), r.setnx("c", "3"), r.setnx("c", "4"), r.get("c")]
  end

  conform "getset, getdel and getex" do |r|
    [
      r.set("k", "v"), r.getset("k", "w"), r.getdel("k"), r.get("k"),
      r.set("k", "v"), r.getex("k", ex: 100), r.ttl("k"), r.getex("k", persist: true), r.ttl("k"), r.getex("missing")
    ]
  end

  conform "append, strlen, getrange and setrange" do |r|
    [r.append("k", "hello"), r.append("k", " world"), r.strlen("k"), r.getrange("k", 0, 4), r.setrange("k", 6, "redis"), r.get("k"), r.strlen("missing")]
  end

  conform "incr, incrby, decr, decrby and incrbyfloat" do |r|
    [r.incr("n"), r.incrby("n", 10), r.decr("n"), r.decrby("n", 3), r.incrbyfloat("f", 1.5), r.incrbyfloat("f", 0.25), r.incrbyfloat("f", -2)]
  end

  conform "incr on a value that isn't an integer", raises: true do |r|
    [r.set("k", "x"), r.incr("k")]
  end

  conform "a string command on another type", raises: true do |r|
    [r.lpush("l", "x"), r.get("l")]
  end

  conform "mset and mget" do |r|
    [r.mset("a", "1", "b", "2"), r.mget("a", "b", "c"), r.mget(["a", "b"])]
  end

  conform "mapped_mset and mapped_mget" do |r|
    [r.mapped_mset({ "a" => "1", "b" => "2" }), r.mapped_mget("a", "b", "c")]
  end

  conform "msetnx and mapped_msetnx" do |r|
    [r.msetnx("a", "1", "b", "2"), r.msetnx("a", "3", "c", "4"), r.mapped_msetnx({ "x" => "1" }), r.mget("a", "b", "c", "x")]
  end

  conform "keys sharing a hash tag" do |r|
    [r.mset("{t}a", "1", "{t}b", "2"), r.mget("{t}a", "{t}b"), r.msetnx("{t}c", "3", "{t}d", "4")]
  end

  conform "binary and non-string values" do |r|
    [r.set("k", "\xFF\x00\xFE".b), r.get("k"), r.set("i", 42), r.get("i"), r.set("f", 1.5), r.get("f"), r.set("s", :sym), r.get("s")]
  end

  conform "set with value and digest conditions" do |r|
    digest = Redis::XXH3.hexdigest("v")
    [
      r.set("k", "v"), r.set("k", "w", ifeq: "x"), r.set("k", "w", ifeq: "v"), r.get("k"),
      r.set("k", "x", ifne: "w"), r.set("k", "x", ifne: "v"), r.set("k", "v", ifeq: "x", get: true),
      r.set("k", "y", ifdeq: "0000000000000000"), r.set("k", "y", ifdeq: digest), r.set("k", "z", ifdne: digest),
      r.set("k", "z", ifdne: Redis::XXH3.hexdigest("z")), r.set("k", "w", ifdne: digest, ex: 100), r.ttl("k"), r.get("k"), r.set("missing", "v", ifeq: "v")
    ]
  end

  conform "digest and delex" do |r|
    [
      r.set("k", "v"), r.digest("k"), r.digest("k") == Redis::XXH3.hexdigest("v"), r.digest("missing"),
      r.delex("k", ifeq: "w"), r.delex("k", ifne: "v"), r.delex("k", ifdne: Redis::XXH3.hexdigest("v")),
      r.delex("k", ifdeq: Redis::XXH3.hexdigest("v")), r.exists?("k"),
      r.set("k", "v"), r.delex("k", ifne: "w"), r.set("k", "v"), r.delex("k", ifeq: "v"), r.set("k", "v"), r.delex("k"), r.delex("missing")
    ]
  end

  conform "digest of a value that isn't a string", raises: true do |r|
    [r.lpush("l", "x"), r.digest("l")]
  end

  conform "increx" do |r|
    [
      r.increx("n"), r.increx("n", by: 10), r.increx("n", by: 5, ubound: 12), r.increx("n", by: 5, ubound: 12, saturate: true),
      r.increx("n", by: -20, lbound: 0), r.increx("n", by: -20, lbound: 0, saturate: true),
      r.increx("f", by: 1.5), r.increx("f", by: 0.25, ubound: 1.6, saturate: true), r.increx("f", by: -3.0, lbound: -1),
      r.increx("t", by: 1, ex: 100), r.ttl("t"), r.increx("t", px: 50_000, enx: true), r.ttl("t"),
      r.increx("t", persist: true), r.ttl("t"), r.increx("t", exat: 4_000_000_000), r.expiretime("t"),
      r.increx("t", pxat: 4_000_000_000_000), r.pexpiretime("t")
    ]
  end

  conform "increx on a value that isn't a number", raises: true do |r|
    [r.set("k", "x"), r.increx("k")]
  end

  conform "lcs" do |r|
    [
      r.mset("{l}a", "ohmytext", "{l}b", "mynewtext"),
      r.lcs("{l}a", "{l}b"), r.lcs("{l}a", "{l}b", len: true), r.lcs("{l}a", "{l}b", idx: true),
      r.lcs("{l}a", "{l}b", idx: true, minmatchlen: 4, withmatchlen: true), r.lcs("{l}a", "{l}b", idx: true, withmatchlen: true),
      r.lcs("{l}a", "{l}missing"), r.lcs("{l}a", "{l}missing", len: true)
    ]
  end

  conform "lcs across slots" do |r|
    [r.set("a", "x"), r.lcs("a", "b")]
  end
end
