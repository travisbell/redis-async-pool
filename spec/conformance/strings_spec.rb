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
end
