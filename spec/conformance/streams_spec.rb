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

  # IDMP and IDMPAUTO need auto-generated ids, which differ between runs, so only which ids repeat is compared.
  conform "xadd with idmp and idmpauto, and xcfgset", modes: [:direct] do |r|
    ids = [
      r.xadd("s", { "a" => "1" }, idmp: ["p", "m1"]), r.xadd("s", { "a" => "2" }, idmp: ["p", "m1"]), r.xadd("s", { "a" => "3" }, idmp: ["p", "m2"]),
      r.xadd("s", { "b" => "1" }, idmpauto: "q"), r.xadd("s", { "b" => "1" }, idmpauto: "q"), r.xadd("s", { "b" => "2" }, idmpauto: "q")
    ]
    configs = [r.xcfgset("s", duration: 60, maxsize: 10), r.xcfgset("s", duration: 120), r.xcfgset("s", maxsize: 5)]
    ids << r.xadd("s", { "a" => "2" }, idmp: ["p", "m1"])
    [ids.map { |id| ids.index(id) }, configs, r.xlen("s"), r.xinfo(:stream, "s").slice("idmp-duration", "idmp-maxsize", "iids-added", "iids-duplicates")]
  end

  conform "xcfgset on a missing stream", raises: true do |r|
    r.xcfgset("missing", duration: 60)
  end

  conform "xadd and xtrim with a reference policy" do |r|
    [
      r.xadd("s", { "a" => "1" }, id: "1-0"), r.xadd("s", { "a" => "2" }, id: "2-0"), r.xgroup(:create, "s", "g", "0"), r.xreadgroup("g", "c", "s", ">", count: 1),
      r.xadd("s", { "a" => "3" }, id: "3-0", maxlen: 1, policy: :acked), r.xrange("s"), r.xtrim("s", 1, policy: :keepref), r.xrange("s"),
      r.xadd("s", { "a" => "4" }, id: "4-0", minid: "4-0", policy: "DELREF"), r.xpending("s", "g"), r.xtrim("s", "5-0", strategy: "MINID", policy: :delref), r.xlen("s")
    ]
  end

  conform "xdelex and xackdel" do |r|
    [
      (1..6).map { |i| r.xadd("{s}a", { "a" => i.to_s }, id: "#{i}-0") }, r.xgroup(:create, "{s}a", "g", "0"), r.xgroup(:create, "{s}a", "h", "0"),
      r.xreadgroup("g", "c", "{s}a", ">"), r.xreadgroup("h", "c", "{s}a", ">", count: 2),
      r.xdelex("{s}a", "1-0", "9-0"), r.xdelex("{s}a", ["2-0"], acked: true), r.xdelex("{s}a", "3-0", delref: true), r.xdelex("missing", "1-0"),
      r.xackdel("{s}a", "g", "2-0"), r.xackdel("{s}a", "g", ["4-0", "9-0"], acked: true), r.xackdel("{s}a", "h", "1-0", "5-0", keepref: true),
      r.xackdel("{s}a", "g", "6-0", delref: true), r.xpending("{s}a", "g"), r.xpending("{s}a", "h"), r.xrange("{s}a"),
      r.xadd("{s}b", { "a" => "1" }, id: "1-0"), r.xdelex("{s}b", "1-0", keepref: true)
    ]
  end

  conform "xnack" do |r|
    [
      r.xadd("s", { "a" => "1" }, id: "1-0"), r.xadd("s", { "a" => "2" }, id: "2-0"), r.xadd("s", { "a" => "3" }, id: "3-0"),
      r.xgroup(:create, "s", "g", "0"), r.xreadgroup("g", "c", "s", ">"),
      r.xnack("s", "g", :fail, "1-0"), r.xnack("s", "g", "SILENT", ["2-0", "9-0"]), r.xnack("s", "g", :fatal, "3-0"), r.xnack("s", "g", :fail, "1-0"),
      r.xnack("s", "g", :fail, "1-0", retrycount: 5, force: true), r.xpending("s", "g")
    ]
  end

  conform "xnack on a missing group", raises: true do |r|
    [r.xadd("s", { "a" => "1" }, id: "1-0"), r.xnack("s", "nope", :fail, "1-0")]
  end

  conform "xsetid and xgroup with entriesread" do |r|
    [
      r.xadd("s", { "a" => "1" }, id: "1-0"), r.xadd("s", { "a" => "2" }, id: "2-0"), r.xsetid("s", "5-0"), r.xsetid("s", "10-0", entriesadded: 10, maxdeletedid: "3-0"),
      r.xgroup(:create, "s", "g", "0", entriesread: 1), r.xgroup(:create, "s", "h", "$", entriesread: 10), r.xgroup(:setid, "s", "g", "1-0", entriesread: 9),
      r.xinfo(:groups, "s"), r.xadd("s", { "a" => "3" }, id: "11-0"), r.xinfo(:stream, "s").slice("last-generated-id", "max-deleted-entry-id", "entries-added")
    ]
  end

  conform "xsetid below the stream's last id", raises: true do |r|
    [r.xadd("s", { "a" => "1" }, id: "5-0"), r.xsetid("s", "1-0")]
  end

  # Entries claimed by XREADGROUP CLAIM carry their idle time, which differs between runs.
  conform "xreadgroup with claim", modes: [:direct] do |r|
    r.xadd("s", { "a" => "1" }, id: "1-0")
    r.xadd("s", { "a" => "2" }, id: "2-0")
    r.xgroup(:create, "s", "g", "0")
    first = r.xreadgroup("g", "c1", "s", ">", count: 1)
    r.xadd("s", { "a" => "3" }, id: "3-0")
    claimed = r.xreadgroup("g", "c2", "s", ">", claim: 0)
    later = r.xreadgroup("g", "c3", "s", ">", claim: 3_600_000, block: 10)
    [first, claimed.transform_values { |entries| entries.map { |entry| entry.values_at(0, 1, 3) } }, later, r.xpending("s", "g")]
  end

  conform "xautoclaim of deleted entries" do |r|
    [
      r.xadd("s", { "a" => "1" }, id: "1-0"), r.xadd("s", { "a" => "2" }, id: "2-0"), r.xadd("s", { "a" => "3" }, id: "3-0"),
      r.xgroup(:create, "s", "g", "0"), r.xreadgroup("g", "c1", "s", ">"), r.xdel("s", "1-0", "3-0"),
      r.xautoclaim("s", "g", "c2", 0, "0-0"), r.xadd("s", { "a" => "4" }, id: "4-0"), r.xreadgroup("g", "c1", "s", ">"), r.xdel("s", "4-0"),
      r.xautoclaim("s", "g", "c2", 0, "0-0", justid: true)
    ]
  end
end
