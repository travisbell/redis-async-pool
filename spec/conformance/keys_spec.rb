# frozen_string_literal: true

RSpec.describe("Keys") do
  conform "del, unlink, exists, exists? and type" do |r|
    [
      r.set("a", "1"), r.set("b", "2"), r.lpush("l", "x"), r.type("a"), r.type("l"), r.type("missing"),
      r.exists("a"), r.exists("a", "b", "missing"), r.exists(["a"]), r.exists?("a"), r.exists?("missing"), r.exists?("a", "missing"),
      r.del("a"), r.del("missing"), r.del(["b"]), r.unlink("l"), r.unlink("missing")
    ]
  end

  conform "del and unlink across slots" do |r|
    [r.set("a", "1"), r.set("b", "2"), r.set("c", "3"), r.del("a", "b"), r.unlink("c", "missing")]
  end

  conform "expire, ttl, persist and their variants" do |r|
    [
      r.set("k", "v"), r.ttl("k"), r.pttl("k"), r.ttl("missing"), r.pttl("missing"),
      r.expire("k", 100), r.ttl("k"), r.expire("k", 200, nx: true), r.expire("k", 50, gt: true), r.expire("k", 200, xx: true), r.expire("k", 300, lt: true),
      r.persist("k"), r.persist("k"), r.ttl("k"), r.expire("missing", 100),
      r.pexpire("k", 100_000), r.ttl("k"), r.pexpire("k", 1, nx: true),
      r.expireat("k", 4_000_000_000), r.expiretime("k"), r.pexpireat("k", 4_000_000_000_000), r.pexpiretime("k"),
      r.expireat("k", 4_000_000_001, gt: true), r.pexpireat("k", 1, lt: true), r.expiretime("missing")
    ]
  end

  conform "keys and randomkey", targets: [:standalone], modes: [:direct] do |r|
    [r.randomkey, r.set("a", "1"), r.randomkey, r.set("b", "2"), r.keys("*").sort, r.keys("a*"), r.keys("z*")]
  end

  conform "rename and renamenx" do |r|
    [r.set("{k}a", "1"), r.set("{k}b", "2"), r.renamenx("{k}a", "{k}b"), r.rename("{k}a", "{k}c"), r.get("{k}c"), r.renamenx("{k}c", "{k}d")]
  end

  conform "rename of a missing key", raises: true do |r|
    r.rename("{k}missing", "{k}b")
  end

  conform "copy" do |r|
    [r.set("{k}a", "1"), r.copy("{k}a", "{k}b"), r.copy("{k}a", "{k}b"), r.copy("{k}a", "{k}b", replace: true), r.get("{k}b")]
  end

  conform "copy and move between databases", targets: [:standalone] do |r|
    [r.set("a", "1"), r.copy("a", "b", db: 1), r.move("a", 1), r.exists?("a"), r.set("c", "1"), r.move("missing", 1)]
  end

  conform "dump" do |r|
    [r.set("k", "v"), r.dump("k"), r.dump("missing")]
  end

  conform "restore", modes: [:direct] do |r|
    r.set("k", "v")
    dump = r.dump("k")
    [r.restore("other", 0, dump), r.get("other"), r.restore("other", 100_000, dump, replace: true), r.ttl("other")]
  end

  conform "restore over an existing key", modes: [:direct], raises: true do |r|
    r.set("k", "v")
    r.restore("k", 0, r.dump("k"))
  end

  conform "object" do |r|
    [r.set("k", "v"), r.object(:encoding, "k"), r.object("refcount", "k"), r.rpush("l", "1"), r.object(:encoding, "l"), r.object(:encoding, "missing")]
  end

  conform "sort" do |r|
    [
      r.rpush("{s}l", ["3", "1", "2"]), r.sort("{s}l"), r.sort("{s}l", order: "desc"), r.sort("{s}l", limit: [0, 2]),
      r.rpush("{s}w", ["b", "a"]), r.sort("{s}w", order: "alpha"),
      r.set("{s}w_1", "3"), r.set("{s}w_2", "1"), r.set("{s}w_3", "2"), r.set("{s}n_1", "one"), r.set("{s}n_2", "two"),
      r.sort("{s}l", by: "{s}w_*", get: ["#", "{s}n_*"]), r.sort("{s}l", store: "{s}dest"), r.lrange("{s}dest", 0, -1)
    ]
  end

  conform "sort_ro" do |r|
    [
      r.rpush("{s}l", ["3", "1", "2"]), r.sort_ro("{s}l"), r.sort_ro("{s}l", order: "desc", limit: [0, 2]),
      r.rpush("{s}w", ["b", "a"]), r.sort_ro("{s}w", order: "alpha"),
      r.set("{s}w_1", "3"), r.set("{s}w_2", "1"), r.set("{s}w_3", "2"), r.set("{s}n_1", "one"),
      r.sort_ro("{s}l", by: "{s}w_*", get: ["#", "{s}n_*"]), r.sort_ro("{s}l", by: "{s}w_*", get: "{s}n_*"), r.sort_ro("{s}missing")
    ]
  end

  conform "bless_get, bless_set and bless_clear" do |r|
    [
      r.set("k", "v"), r.bless_get("k"), r.bless_set("k", "NO-EVICT"), r.bless_set("k", "NO-EVICT"), r.bless_get("k"),
      r.bless_clear("k", "NO-EVICT"), r.bless_clear("k", "NO-EVICT"), r.bless_get("k")
    ]
  end

  conform "bless on a missing key", raises: true do |r|
    r.bless_set("missing", "NO-EVICT")
  end

  conform "bless with an unknown flag", raises: true do |r|
    [r.set("k", "v"), r.bless_set("k", "BOGUS")]
  end

  conform "bless_scan", targets: [:standalone] do |r|
    [r.set("a", "1"), r.set("b", "2"), r.set("c", "3"), r.bless_set("a", "NO-EVICT"), r.bless_set("b", "NO-EVICT"), r.bless_scan(0, "NO-EVICT"), r.bless_scan(0, "NO-EVICT", count: 1)]
  end

  conform "bless_scan_each", targets: [:standalone], modes: [:direct] do |r|
    r.set("a", "1")
    r.set("b", "2")
    r.bless_set("a", "NO-EVICT")
    [r.bless_scan_each("NO-EVICT").to_a, r.bless_scan_each("NO-EVICT", count: 1).to_a]
  end

  # Like scan, a cluster bless_scan walks every node, one per call, encoding the node in the cursor.
  conform "bless_scan on a cluster", targets: [:cluster], modes: [:direct] do |r|
    keys = ["a", "b", "c", "d", "e"]
    keys.each { |key| r.set(key, "1") && r.bless_set(key, "NO-EVICT") }
    cursor = 0
    found = []
    loop do
      cursor, batch = r.bless_scan(cursor, "NO-EVICT", count: 100)
      found.concat(batch)
      break if cursor == "0"
    end
    [found.sort, r.bless_scan_each("NO-EVICT").to_a.sort]
  end

  conform "scan", targets: [:standalone] do |r|
    [r.set("a", "1"), r.set("b", "2"), r.lpush("l", "x"), r.scan(0), r.scan(0, match: "a*", count: 100), r.scan(0, type: "list")]
  end

  conform "scan_each", targets: [:standalone], modes: [:direct] do |r|
    r.set("a", "1")
    r.lpush("l", "x")
    [r.scan_each.to_a.sort, r.scan_each(match: "a*").to_a, r.scan_each(type: "list").to_a]
  end

  conform "scan on a cluster", targets: [:cluster], modes: [:direct] do |r|
    r.set("a", "1")
    r.set("b", "2")
    [r.scan_each.to_a.sort, r.keys("*").sort]
  end
end
