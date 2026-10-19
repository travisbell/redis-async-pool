# frozen_string_literal: true

RSpec.describe("Lists") do
  conform "push, pop, range, len and index" do |r|
    [
      r.lpush("l", "a"), r.lpush("l", ["b", "c"]), r.rpush("l", "d"), r.rpush("l", ["e", "f"]),
      r.lpushx("l", "g"), r.rpushx("l", "h"), r.lpushx("missing", "x"), r.rpushx("missing", "x"),
      r.lrange("l", 0, -1), r.llen("l"), r.lindex("l", 1), r.lindex("l", 100),
      r.lpop("l"), r.rpop("l"), r.lpop("l", 2), r.rpop("l", 2), r.lpop("missing"), r.lrange("l", 0, -1)
    ]
  end

  conform "linsert, lset, lrem and ltrim" do |r|
    [
      r.rpush("l", ["a", "b", "a", "c"]), r.linsert("l", :before, "b", "x"), r.linsert("l", "AFTER", "c", "y"),
      r.lset("l", 0, "z"), r.lrem("l", 0, "a"), r.ltrim("l", 0, 2), r.lrange("l", 0, -1)
    ]
  end

  conform "lset out of range", raises: true do |r|
    [r.rpush("l", "a"), r.lset("l", 5, "x")]
  end

  conform "lmove and rpoplpush" do |r|
    [
      r.rpush("{l}a", ["1", "2", "3"]), r.lmove("{l}a", "{l}b", "LEFT", "RIGHT"), r.lmove("{l}a", "{l}b", :right, :left),
      r.rpoplpush("{l}a", "{l}b"), r.lrange("{l}b", 0, -1), r.lmove("{l}missing", "{l}b", "LEFT", "LEFT")
    ]
  end

  conform "lmpop" do |r|
    [r.rpush("{l}a", ["1", "2", "3"]), r.lmpop("{l}missing", "{l}a"), r.lmpop("{l}a", modifier: "RIGHT", count: 5), r.lmpop("{l}a")]
  end

  conform "blpop and brpop" do |r|
    [
      r.rpush("{l}a", ["1", "2"]), r.blpop("{l}a", timeout: 0.1), r.brpop("{l}missing", "{l}a", timeout: 0.1),
      r.blpop("{l}a", timeout: 0.1), r.brpop(["{l}a"], timeout: 0.1)
    ]
  end

  # redis-rb's cluster client sends BLMPOP to a random node (Redis reports no fixed key position for it), so
  # in a pipeline it runs after the other commands whenever it's redirected. See "Cluster pipelines".
  conform "blmove, brpoplpush and blmpop", except: ["cluster/pipelined"] do |r|
    [
      r.rpush("{l}a", ["1", "2", "3"]), r.blmove("{l}a", "{l}b", "LEFT", "RIGHT", timeout: 0.1), r.brpoplpush("{l}a", "{l}b", timeout: 0.1),
      r.blmpop(0.1, "{l}a", modifier: "LEFT", count: 2), r.blmpop(0.1, "{l}a"), r.blmove("{l}a", "{l}b", "LEFT", "LEFT", timeout: 0.1),
      r.lrange("{l}b", 0, -1)
    ]
  end
end
