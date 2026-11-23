# frozen_string_literal: true

RSpec.describe("JSON") do
  conform "json_set, json_get, json_type, json_del and json_forget" do |r|
    [
      r.json_set("{j}", "$", { "a" => 1, "b" => { "c" => "x", "d" => [1, 2] }, "e" => nil }),
      r.json_get("{j}"), r.json_get("{j}", "$.a"), r.json_get("{j}", "$.b.c", "$.b.d"), r.json_get("{j}", ".b"), r.json_get("{j}", "$.z"),
      r.json_get("{j}", "$.b", raw: true), r.json_get("{j}missing"),
      r.json_type("{j}"), r.json_type("{j}", "$.b.d"), r.json_type("{j}", ".a"), r.json_type("{j}", "$..c"), r.json_type("{j}missing"),
      r.json_del("{j}", "$.b.c"), r.json_forget("{j}", "$.z"), r.json_del("{j}", ".e"), r.json_get("{j}"),
      r.json_forget("{j}"), r.json_del("{j}missing"), r.json_get("{j}")
    ]
  end

  conform "json_set with nx, xx, raw and fpha" do |r|
    [
      r.json_set("{j}", "$", { "a" => 1 }, xx: true), r.json_set("{j}", "$", { "a" => 1 }, nx: true), r.json_set("{j}", "$", { "a" => 2 }, nx: true),
      r.json_set("{j}", "$.a", 3, xx: true), r.json_set("{j}", "$.b", 4, xx: true), r.json_set("{j}", "$.b", "[1,\"two\"]", raw: true),
      r.json_get("{j}"), r.json_set("{j}v", "$", [0.5, 1.5, -2.25], fpha: :fp32), r.json_get("{j}v"), r.json_type("{j}v", "$[0]"),
      r.json_set("{j}v", "$", [1.0, 2.0], fpha: "bf16"), r.json_get("{j}v", "$[1]")
    ]
  end

  conform "json_set with nx and xx", raises: true do |r|
    r.json_set("{j}", "$", 1, nx: true, xx: true)
  end

  conform "json_set with an unknown fpha type", raises: true do |r|
    r.json_set("{j}", "$", [1.0], fpha: :fp8)
  end

  conform "json_set below a missing key", raises: true do |r|
    r.json_set("{j}missing", "$.a", 1)
  end

  conform "json_mset and json_mget" do |r|
    [
      r.json_mset("{j}a", "$", { "n" => 1 }, "{j}b", "$", { "n" => 2, "m" => "x" }), r.json_mset("{j}c", "$", "{\"n\":3}", raw: true),
      r.json_mget("{j}a", "{j}b", "{j}c", "{j}missing", "$.n"), r.json_mget(["{j}a", "{j}b"], "$.m"), r.json_mget("{j}a", "{j}b", ".n"),
      r.json_mget("{j}b", "$", raw: true)
    ]
  end

  conform "json_mset with an incomplete triplet", raises: true do |r|
    r.json_mset("{j}a", "$")
  end

  conform "json_arrappend, json_arrinsert, json_arrindex, json_arrlen, json_arrpop and json_arrtrim" do |r|
    [
      r.json_set("{j}", "$", { "a" => [1, 2], "o" => { "a" => ["x"] }, "s" => "str" }),
      r.json_arrappend("{j}", "$.a", 3, "four", { "five" => 5 }), r.json_arrappend("{j}", "$..a", nil), r.json_arrappend("{j}", ".a", "6", raw: true),
      r.json_arrinsert("{j}", "$.a", 0, 0), r.json_arrinsert("{j}", "$.a", -1, "[7]", raw: true), r.json_arrinsert("{j}", "$.s", 0, 1),
      r.json_get("{j}", "$.a"), r.json_arrlen("{j}", "$.a"), r.json_arrlen("{j}", "$..a"), r.json_arrlen("{j}", ".a"), r.json_arrlen("{j}", "$.s"),
      r.json_arrlen("{j}missing", ".a"),
      r.json_arrindex("{j}", "$.a", 2), r.json_arrindex("{j}", "$.a", "four", start: 3), r.json_arrindex("{j}", "$.a", 2, start: 0, stop: 2),
      r.json_arrindex("{j}", "$.a", 1, stop: 1), r.json_arrindex("{j}", "$.a", "\"four\"", raw: true), r.json_arrindex("{j}", "$..a", "x"),
      r.json_arrpop("{j}", "$.a"), r.json_arrpop("{j}", "$.a", 0), r.json_arrpop("{j}", ".a", -2), r.json_arrpop("{j}", "$..a", 0, raw: true),
      r.json_arrpop("{j}", "$.s"), r.json_arrtrim("{j}", "$.a", 1, 2), r.json_arrtrim("{j}", "$..a", 0, 0), r.json_get("{j}"),
      r.json_set("{j}arr", "$", [1, 2, 3]), r.json_arrpop("{j}arr"), r.json_arrlen("{j}arr"), r.json_arrpop("{j}arr", ".", 0, raw: true), r.json_get("{j}arr")
    ]
  end

  conform "json_arrpop with an index and no path", raises: true do |r|
    r.json_arrpop("{j}", nil, 0)
  end

  conform "json_arrlen of a missing key with a JSONPath", raises: true do |r|
    r.json_arrlen("{j}missing", "$")
  end

  conform "json_objkeys, json_objlen, json_strappend, json_strlen and json_toggle" do |r|
    [
      r.json_set("{j}", "$", { "o" => { "x" => 1, "y" => { "z" => true } }, "s" => "ab", "t" => true, "n" => { "s" => "c" } }),
      r.json_objkeys("{j}"), r.json_objkeys("{j}", "$.o"), r.json_objkeys("{j}", "$..y"), r.json_objkeys("{j}", ".o"), r.json_objkeys("{j}", "$.s"),
      r.json_objlen("{j}"), r.json_objlen("{j}", "$.o"), r.json_objlen("{j}", ".o.y"), r.json_objlen("{j}", "$.t"), r.json_objkeys("{j}missing"),
      r.json_strappend("{j}", "$.s", "cd"), r.json_strappend("{j}", "$..s", "!"), r.json_strappend("{j}", ".s", "\"?\"", raw: true),
      r.json_strlen("{j}", "$.s"), r.json_strlen("{j}", "$..s"), r.json_strlen("{j}", ".n.s"), r.json_strlen("{j}", "$.t"),
      r.json_toggle("{j}", "$.t"), r.json_toggle("{j}", "$..z"), r.json_toggle("{j}", ".t"), r.json_toggle("{j}", "$.s"), r.json_get("{j}"),
      r.json_set("{j}str", "$", "abc"), r.json_strlen("{j}str"), r.json_strappend("{j}str", "$", "d"), r.json_strlen("{j}missing")
    ]
  end

  conform "json_numincrby, json_clear and json_merge" do |r|
    [
      r.json_set("{j}", "$", { "n" => 1, "f" => 1.5, "o" => { "n" => 10 }, "a" => [1, 2], "s" => "x" }),
      r.json_numincrby("{j}", "$.n", 2), r.json_numincrby("{j}", "$..n", 1), r.json_numincrby("{j}", ".f", 0.25), r.json_numincrby("{j}", "$.s", 1),
      r.json_numincrby("{j}", "$.missing", 1),
      r.json_merge("{j}", "$", { "o" => { "m" => true, "n" => nil }, "new" => [1] }), r.json_merge("{j}", "$.a", "[9]", raw: true),
      r.json_merge("{j}", "$.o", { "deep" => { "x" => 1 } }), r.json_get("{j}"),
      r.json_clear("{j}", "$.o"), r.json_clear("{j}", "$.*"), r.json_get("{j}"), r.json_clear("{j}"), r.json_get("{j}"),
      r.json_numincrby("{j}", ".missing", 1)
    ]
  end

  # JSON.DEBUG MEMORY's key follows a keyword, which redis-cluster-client doesn't locate: it sends the command to a
  # random node and follows the MOVED. In a cluster pipeline the redirected command runs after the rest of the
  # pipeline, so whether it sees the later commands' writes depends on the node it happened to pick.
  conform "json_debug_memory", except: ["cluster/pipelined"] do |r|
    [
      r.json_set("{j}", "$", { "o" => { "n" => 10 }, "a" => [1, 2], "s" => "x" }),
      r.json_debug_memory("{j}"), r.json_debug_memory("{j}", "$.o"), r.json_debug_memory("{j}", ".a"), r.json_debug_memory("{j}missing"),
      r.json_del("{j}", "$.o"), r.json_debug_memory("{j}", "$.o")
    ]
  end

  conform "json_clear of a missing key", raises: true do |r|
    r.json_clear("{j}missing")
  end

  conform "json_get of a non-JSON key", raises: true do |r|
    [r.set("{j}k", "v"), r.json_get("{j}k")]
  end
end
