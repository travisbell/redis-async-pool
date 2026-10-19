# frozen_string_literal: true

RSpec.describe("Streams") do
  conform "xadd, xlen, xrange, xrevrange, xdel and xtrim" do |r|
    [
      r.xadd("s", { "a" => "1" }, id: "1-0"), r.xadd("s", { a: 2, b: 3 }, id: "2-0"), r.xadd("s", { "c" => "4" }, id: "3-0", maxlen: 10, approximate: true),
      r.xadd("missing", { "x" => "1" }, nomkstream: true), r.xlen("s"),
      r.xrange("s"), r.xrange("s", "2-0", "+", count: 1), r.xrevrange("s"), r.xrevrange("s", "+", "-", count: 1),
      r.xdel("s", "1-0"), r.xdel("s", ["2-0", "9-0"]), r.xadd("s", { "d" => "5" }, id: "4-0"), r.xtrim("s", 1), r.xtrim("s", "4-0", strategy: "MINID"),
      r.xrange("s")
    ]
  end

  conform "xadd with an id that isn't increasing", raises: true do |r|
    [r.xadd("s", { "a" => "1" }, id: "2-0"), r.xadd("s", { "a" => "1" }, id: "1-0")]
  end

  conform "xread" do |r|
    [
      r.xadd("{s}a", { "a" => "1" }, id: "1-0"), r.xadd("{s}b", { "b" => "1" }, id: "1-0"),
      r.xread("{s}a", "0-0"), r.xread(["{s}a", "{s}b"], ["0-0", "0-0"], count: 1), r.xread("{s}a", "$", block: 50), r.xread("{s}a", "1-0")
    ]
  end

  conform "consumer groups: xgroup, xreadgroup, xack and xpending" do |r|
    [
      r.xadd("s", { "a" => "1" }, id: "1-0"), r.xadd("s", { "a" => "2" }, id: "2-0"),
      r.xgroup(:create, "s", "g", "0"), r.xgroup(:create, "new", "g", "$", mkstream: true), r.xgroup(:createconsumer, "s", "g", "c2"),
      r.xreadgroup("g", "c", "s", ">"), r.xreadgroup("g", "c", "s", ">", count: 1, block: 50), r.xreadgroup("g", "c", ["s"], ["0"], noack: true),
      r.xpending("s", "g"), r.xack("s", "g", "1-0"), r.xack("s", "g", ["2-0", "9-0"]), r.xpending("s", "g"),
      r.xgroup(:setid, "s", "g", "0"), r.xgroup(:delconsumer, "s", "g", "c2"), r.xgroup(:destroy, "s", "g"), r.xgroup(:destroy, "s", "g")
    ]
  end

  conform "xgroup create on an existing group", raises: true do |r|
    [r.xgroup(:create, "s", "g", "$", mkstream: true), r.xgroup(:create, "s", "g", "$")]
  end

  # Pending entries carry their idle time, which differs between runs.
  conform "xpending with a range", modes: [:direct] do |r|
    r.xadd("s", { "a" => "1" }, id: "1-0")
    r.xgroup(:create, "s", "g", "0")
    r.xreadgroup("g", "c", "s", ">")
    [r.xpending("s", "g", "-", "+", 10), r.xpending("s", "g", "-", "+", 10, "c"), r.xpending("s", "g", "-", "+", 10, idle: 100_000)].map do |entries|
      entries.map { |entry| entry.except("elapsed") }
    end
  end

  conform "xclaim and xautoclaim" do |r|
    [
      r.xadd("s", { "a" => "1" }, id: "1-0"), r.xadd("s", { "a" => "2" }, id: "2-0"), r.xgroup(:create, "s", "g", "0"), r.xreadgroup("g", "c1", "s", ">"),
      r.xclaim("s", "g", "c2", 0, "1-0"), r.xclaim("s", "g", "c2", 0, "1-0", justid: true), r.xclaim("s", "g", "c2", 0, ["1-0", "2-0"], idle: 0, force: true),
      r.xautoclaim("s", "g", "c3", 0, "0-0"), r.xautoclaim("s", "g", "c3", 0, "0-0", count: 1, justid: true)
    ]
  end

  # Consumer info carries idle times, which differ between runs.
  conform "xinfo", modes: [:direct] do |r|
    r.xadd("s", { "a" => "1" }, id: "1-0")
    r.xgroup(:create, "s", "g", "0")
    r.xreadgroup("g", "c", "s", ">")
    [r.xinfo(:stream, "s"), r.xinfo(:groups, "s"), r.xinfo(:consumers, "s", "g").map { |consumer| consumer.except("idle", "inactive") }]
  end
end
