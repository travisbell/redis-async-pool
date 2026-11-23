# frozen_string_literal: true

RSpec.describe("Vector sets") do
  conform "vadd, vcard, vdim, vismember, vrem and vrange" do |r|
    [
      r.vadd("v", [1, 0, 0], "a"), r.vadd("v", [0, 1, 0], "b"), r.vadd("v", [0, 1, 0], "b"),
      r.vadd("v", [0.0, 0.0, 1.0].pack("e*"), "c"), r.vadd("{v}m", [1, 1, 0], "d", ef: 100, m: 8, cas: true),
      r.vcard("v"), r.vcard("missing"), r.vdim("v"), r.vismember("v", "a"), r.vismember("v", "x"), r.vismember("missing", "a"),
      r.vrange("v", "-", "+"), r.vrange("v", "(a", "[c", 1), r.vrange("v", "(b", "+", -1), r.vrange("missing", "-", "+"),
      r.vrem("v", "a"), r.vrem("v", "a"), r.vrem("missing", "a"), r.vcard("v"), r.vrange("v", "-", "+")
    ]
  end

  conform "vadd with reduce", modes: [:direct] do |r|
    [r.vadd("v", [1, 2, 3, 4], "a", reduce: 2), r.vdim("v"), r.vcard("v")]
  end

  # The cluster client doesn't find vector set commands in COMMAND's reply (it lists module commands in
  # upper case), so it sends them to a random node and follows the redirection; in a pipeline an error
  # reply then comes back alone or in a CommandErrorCollection depending on the node reached.
  conform "vadd with a vector of the wrong dimension", except: ["cluster/pipelined"], raises: true do |r|
    [r.vadd("v", [1, 0, 0], "a"), r.vadd("v", [1, 0], "b")]
  end

  # Vector set commands go to a random cluster node (see above), so a pipeline's error differs between runs.
  conform "vdim of a missing key", except: ["cluster/pipelined"], raises: true do |r|
    r.vdim("missing")
  end

  conform "vemb" do |r|
    [
      r.vadd("v", [3, 4, 0], "a", quantization: :noquant), r.vadd("{v}q", [1, 0, 0], "a"), r.vadd("{v}b", [1, -1, 0], "a", quantization: :bin),
      r.vemb("v", "a"), r.vemb("v", "a", raw: true), r.vemb("{v}q", "a"), r.vemb("{v}q", "a", raw: true), r.vemb("{v}b", "a", raw: true),
      r.vemb("v", "missing"), r.vemb("missing", "a")
    ]
  end

  conform "vsetattr and vgetattr" do |r|
    [
      r.vadd("v", [1, 0], "a", attributes: { "color" => "red", "size" => 3 }), r.vadd("v", [0, 1], "b"), r.vgetattr("v", "a"), r.vgetattr("v", "a", raw: true),
      r.vgetattr("v", "b"), r.vsetattr("v", "b", { kind: "fruit" }), r.vgetattr("v", "b"), r.vsetattr("v", "b", '{"n": 1}'), r.vgetattr("v", "b", raw: true),
      r.vsetattr("v", "b", nil), r.vgetattr("v", "b"), r.vsetattr("v", "missing", { x: 1 }), r.vsetattr("missing", "a", { x: 1 }), r.vgetattr("missing", "a")
    ]
  end

  # Vector set commands go to a random cluster node (see above), so a pipeline's error differs between runs.
  conform "vadd with a different quantization than the set's", except: ["cluster/pipelined"], raises: true do |r|
    [r.vadd("v", [1, 0, 0], "a"), r.vadd("v", [0, 1, 0], "b", quantization: :noquant)]
  end

  # TRUTH makes the search an exact linear scan, so the results don't depend on the HNSW graph.
  conform "vsim" do |r|
    [
      r.vadd("v", [1, 0, 0], "a", quantization: :noquant, attributes: { "year" => 2000 }), r.vadd("v", [0.9, 0.1, 0], "b", quantization: :noquant),
      r.vadd("v", [0, 1, 0], "c", quantization: :noquant, attributes: { "year" => 2020 }), r.vadd("v", [-1, 0, 0], "d", quantization: :noquant),
      r.vsim("v", element: "a", truth: true), r.vsim("v", vector: [1, 0, 0], count: 2, truth: true), r.vsim("v", vector: [0, 1, 0].pack("e*"), count: 1, truth: true),
      r.vsim("v", element: "a", with_scores: true, count: 3, truth: true), r.vsim("v", element: "a", with_attribs: true, truth: true, count: 3),
      r.vsim("v", element: "a", with_scores: true, with_attribs: true, truth: true, count: 2), r.vsim("v", element: "a", with_attribs: true, raw: true, truth: true, count: 1),
      r.vsim("v", element: "a", filter: ".year > 2010", truth: true), r.vsim("v", element: "a", filter: ".year >= 2000", filter_ef: 10, ef: 50, truth: true, nothread: true),
      r.vsim("v", element: "a", epsilon: 0.5, truth: true), r.vsim("missing", vector: [1, 0, 0])
    ]
  end

  # Vector set commands go to a random cluster node (see above), so a pipeline's error differs between runs.
  conform "vsim of a missing element", except: ["cluster/pipelined"], raises: true do |r|
    [r.vadd("v", [1, 0, 0], "a"), r.vsim("v", element: "missing")]
  end

  # The HNSW graph's layers are random, so only the neighbors (and their scores) are compared, not the layers.
  conform "vlinks", modes: [:direct] do |r|
    r.vadd("v", [1, 0, 0], "a", quantization: :noquant)
    r.vadd("v", [0, 1, 0], "b", quantization: :noquant)
    r.vadd("v", [0, 0, 1], "c", quantization: :noquant)
    [
      r.vlinks("v", "a").flatten.uniq.sort, r.vlinks("v", "a", with_scores: true).reduce({}, :merge).sort, r.vlinks("v", "a", withscores: true).class,
      r.vlinks("v", "missing"), r.vlinks("missing", "a")
    ]
  end

  conform "vlinks of a missing key or element" do |r|
    [r.vadd("v", [1, 0], "a"), r.vlinks("v", "missing"), r.vlinks("v", "missing", with_scores: true), r.vlinks("missing", "a")]
  end

  # VINFO reports graph details (levels, node uids) that depend on the HNSW graph's random layers, and a
  # server-wide counter (vset-uid).
  conform "vinfo", modes: [:direct] do |r|
    r.vadd("v", [1, 0, 0], "a")
    r.vadd("v", [0, 1, 0], "b", attributes: { "x" => 1 })
    r.vadd("{v}b", [1, 0], "a", quantization: :bin)
    info = r.vinfo("v")
    [info.keys.sort, info.slice("quant-type", "hnsw-m", "vector-dim", "size", "attributes-count"), r.vinfo("{v}b")["quant-type"], r.vinfo("missing")]
  end

  conform "vinfo of a missing key" do |r|
    r.vinfo("missing")
  end

  # VRANDMEMBER picks members at random.
  conform "vrandmember", modes: [:direct] do |r|
    r.vadd("v", [1, 0], "a")
    r.vadd("v", [0, 1], "b")
    r.vadd("v", [1, 1], "c")
    [
      %w[a b c].include?(r.vrandmember("v")), r.vrandmember("v", 2).uniq.size, r.vrandmember("v", 10).sort, r.vrandmember("v", -5).size,
      (r.vrandmember("v", -5) - %w[a b c]), r.vrandmember("missing"), r.vrandmember("missing", 2)
    ]
  end

  conform "vrandmember of one member" do |r|
    [r.vadd("v", [1, 0], "a"), r.vrandmember("v"), r.vrandmember("v", 3), r.vrandmember("v", -2), r.vrandmember("missing"), r.vrandmember("missing", 2)]
  end
end
