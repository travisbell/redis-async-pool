# frozen_string_literal: true

RSpec.describe("Arrays") do
  conform "arset, arget, armset and armget" do |r|
    [
      r.arset("a", 0, "x", "y"), r.arset("a", 5, "z"), r.arset("a", 1, "Y"), r.arget("a", 1), r.arget("a", 3), r.arget("missing", 0),
      r.armset("a", { 2 => "c", 10 => "k" }), r.armset("a", [3, "d"], [4, "e"]), r.armset("a", 6, "f"),
      r.armget("a", 0, 1, 9), r.armget("a", [10, 2]), r.armget("missing", 0, 1)
    ]
  end

  conform "argetrange, arlen, arcount and arscan" do |r|
    [
      r.armset("a", 0, "x", 1, "y", 3, "d", 4, "e", 9, "j"),
      r.argetrange("a", 0, 4), r.argetrange("a", 4, 0), r.argetrange("missing", 0, 1),
      r.arlen("a"), r.arcount("a"), r.arlen("missing"), r.arcount("missing"),
      r.arscan("a", 0, 20), r.arscan("a", 9, 0, limit: 2), r.arscan("missing", 0, 9)
    ]
  end

  conform "ardel and ardelrange" do |r|
    [
      r.armset("a", 0, "a", 1, "b", 2, "c", 3, "d", 4, "e", 5, "f", 6, "g", 10, "k"),
      r.ardel("a", 0, 99), r.ardel("a", [1, 2]), r.ardelrange("a", 3, 4, [10, 10]), r.ardelrange("a", 6, 5),
      r.arscan("a", 0, 20), r.ardel("missing", 0), r.ardelrange("missing", 0, 1),
      r.ardelrange("a", 0, 100), r.exists?("a")
    ]
  end

  conform "arinfo" do |r|
    r.armset("a", 0, "x", 1, "y", 5, "z")
    info = r.arinfo("a")
    full = r.arinfo("a", full: true)
    [info, full.transform_values(&:class)]
  end

  conform "arinfo of a missing key", raises: true do |r|
    r.arinfo("missing")
  end

  conform "arinsert, arnext, arseek and arlastitems" do |r|
    [
      r.arnext("i"), r.arinsert("i", "a", "b"), r.arnext("i"), r.arinsert("i", "c"),
      r.arseek("i", 10), r.arseek("missing", 1), r.arinsert("i", "d"), r.arnext("i"),
      r.arlastitems("i", 2), r.arlastitems("i", 10, rev: true), r.arlastitems("missing", 2)
    ]
  end

  conform "arring" do |r|
    [r.arring("r", 3, "a", "b", "c", "d"), r.argetrange("r", 0, 2), r.arring("r", 3, "e"), r.arlastitems("r", 3), r.arlen("r")]
  end

  conform "argrep" do |r|
    [
      r.armset("g", 0, "apple", 1, "banana", 2, "Cherry", 4, "10", 5, "3.5"),
      r.argrep("g", "-", "+", match: "an"), r.argrep("g", 0, 9, glob: "a*", exact: "cherry", nocase: true, with_values: true),
      r.argrep("g", 5, 0, re: "^[0-9]", limit: 1), r.argrep("g", "-", "+", match: ["a", "e"], logic: :and),
      r.argrep("g", 0, 9, exact: "cherry"), r.argrep("missing", "-", "+", match: "a")
    ]
  end

  conform "arop" do |r|
    [
      r.armset("n", 0, "apple", 2, "10", 3, "3.5", 4, "6"),
      r.arop("n", 2, 4, :sum), r.arop("n", 0, 9, :min), r.arop("n", 0, 9, "max"),
      r.arop("n", 2, 4, :or), r.arop("n", 2, 4, :and), r.arop("n", 2, 4, :xor),
      r.arop("n", 0, 9, :match, value: "apple"), r.arop("n", 0, 9, :used), r.arop("missing", 0, 9, :sum)
    ]
  end

  conform "an array command on another type", raises: true do |r|
    [r.set("s", "x"), r.arget("s", 0)]
  end
end
