# frozen_string_literal: true

RSpec.describe("Bitmaps") do
  conform "setbit, getbit, bitcount and bitpos" do |r|
    [
      r.setbit("b", 7, 1), r.setbit("b", 7, 0), r.setbit("b", 9, 1), r.getbit("b", 9), r.getbit("b", 100),
      r.bitcount("b"), r.bitcount("b", 1, 1), r.bitcount("b", 0, 15, scale: "bit"),
      r.bitpos("b", 1), r.bitpos("b", 0, 1), r.bitpos("b", 1, 0, 15, scale: "bit"), r.bitpos("missing", 1)
    ]
  end

  conform "bitop" do |r|
    [r.set("{b}a", "\xF0"), r.set("{b}b", "\x0F"), r.bitop("or", "{b}d", "{b}a", "{b}b"), r.get("{b}d"), r.bitop(:not, "{b}n", "{b}a"), r.get("{b}n")]
  end

  conform "bitop across slots" do |r|
    [r.set("a", "\xF0"), r.set("b", "\x0F"), r.bitop("and", "d", "a", "b")]
  end
end

RSpec.describe("HyperLogLog") do
  conform "pfadd, pfcount and pfmerge" do |r|
    [
      r.pfadd("{h}a", "x"), r.pfadd("{h}a", "x"), r.pfadd("{h}a", ["y", "z"]), r.pfadd("{h}b", "w"),
      r.pfcount("{h}a"), r.pfcount("{h}a", "{h}b"), r.pfmerge("{h}m", "{h}a", "{h}b"), r.pfcount("{h}m"), r.pfcount("missing")
    ]
  end
end

RSpec.describe("Geo") do
  places = [13.361389, 38.115556, "Palermo", 15.087269, 37.502669, "Catania"]

  conform "geoadd, geopos, geodist and geohash" do |r|
    [
      r.geoadd("g", *places), r.geoadd("g", [13.361389, 38.115556, "Palermo"]),
      r.geopos("g", "Palermo"), r.geopos("g", ["Palermo", "Nowhere"]), r.geodist("g", "Palermo", "Catania"), r.geodist("g", "Palermo", "Catania", "km"),
      r.geodist("g", "Palermo", "Nowhere"), r.geohash("g", "Palermo"), r.geohash("g", ["Palermo", "Catania"])
    ]
  end

  conform "georadius and georadiusbymember" do |r|
    [
      r.geoadd("g", *places),
      r.georadius("g", 15, 37, 200, "km"), r.georadius("g", 15, 37, 200, "km", "WITHDIST", "WITHCOORD", sort: "asc"),
      r.georadius("g", 15, 37, 200, "km", count: 1, sort: "desc"),
      r.georadiusbymember("g", "Palermo", 200, "km"), r.georadiusbymember("g", "Palermo", 200, "km", "WITHDIST", sort: "asc", count: 1)
    ]
  end
end
