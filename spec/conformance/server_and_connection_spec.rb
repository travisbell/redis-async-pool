# frozen_string_literal: true

RSpec.describe("Server") do
  # Pipelines route by key alone, so this keyless command goes to a random cluster node in both clients.
  conform "dbsize, flushdb and flushall", except: ["cluster/pipelined"] do |r|
    [r.set("a", "1"), r.dbsize, r.flushdb, r.dbsize, r.set("a", "1"), r.flushall, r.dbsize, r.flushdb(async: true), r.flushall(async: true)]
  end

  # Server state (uptime, clocks, counters) differs between runs, so only its shape is compared.
  conform "info", modes: [:direct] do |r|
    info = r.info
    commandstats = r.info("commandstats")
    [info.class, info.key?("redis_version"), r.info("server")["redis_version"], r.info(:keyspace), commandstats.class, commandstats.values.first&.keys&.sort]
  end

  conform "time and lastsave", modes: [:direct] do |r|
    [r.time.map(&:class), r.lastsave.class]
  end

  conform "save, bgsave and bgrewriteaof", targets: [:standalone] do |r|
    [r.save, r.bgsave]
  end

  conform "bgrewriteaof", targets: [:standalone] do |r|
    r.bgrewriteaof
  end

  conform "config" do |r|
    [r.config(:get, "maxmemory"), r.config(:get, "*max-*-entries*"), r.config(:set, "maxmemory-samples", 5), r.config(:resetstat)]
  end

  # Pipelines route by key alone, so this keyless command goes to a random cluster node in both clients.
  conform "config rewrite without a config file", except: ["cluster/pipelined"], raises: true do |r|
    r.config(:rewrite)
  end

  conform "client" do |r|
    [r.client(:getname), r.client(:setname, "conformance"), r.client(:getname), r.client("no-evict", "off")]
  end

  # The list includes connection ids, ages and addresses, which differ between runs.
  conform "client list and info", modes: [:direct] do |r|
    [r.client(:list).first.keys.sort, r.client(:info).class, r.client(:id).class]
  end

  conform "slowlog" do |r|
    [r.slowlog(:reset), r.slowlog(:len), r.slowlog(:get), r.slowlog(:get, 1)]
  end

  # DEBUG has no key, so both clients send it to a random cluster node, which the error names.
  conform "debug", except: ["cluster/direct", "cluster/pipelined"], raises: true do |r|
    [r.set("k", "v"), r.debug(:object, "k")]
  end

  conform "monitor", targets: [:standalone], modes: [:direct] do |r|
    lines = []
    r.monitor do |line|
      lines << line
      Conformance.side.set("k", "v") if lines.one?
      break if lines.size == 2
    end
    [lines.first, lines.last[/"set" "k" "v"/]]
  end
end

RSpec.describe("Connection") do
  conform "ping and echo" do |r|
    [r.ping, r.ping("hello"), r.echo("hello"), r.echo(42)]
  end

  conform "select", targets: [:standalone] do |r|
    [r.select(1), r.set("k", "v"), r.select(0), r.get("k"), r.select(1), r.get("k")]
  end

  # Pipelines route by key alone, so this keyless command goes to a random cluster node in both clients.
  conform "select on a cluster", targets: [:cluster], except: ["cluster/pipelined"] do |r|
    r.select(1)
  end

  # Pipelines route by key alone, so this keyless command goes to a random cluster node in both clients.
  conform "auth without a password configured", except: ["cluster/pipelined"], raises: true do |r|
    r.auth("secret")
  end

  conform "quit, then a command", modes: [:direct] do |r|
    [r.quit, r.ping]
  end

  # An unknown command has no key, so both clients send it to a random cluster node, which the error names.
  conform "an unknown command", except: ["cluster/direct", "cluster/pipelined"], raises: true do |r|
    r.call("NOSUCHCOMMAND", "x")
  end

  conform "sentinel against a server that isn't one", targets: [:standalone], raises: true do |r|
    r.sentinel(:masters)
  end
end

RSpec.describe("Cluster") do
  conform "cluster and asking", targets: [:cluster], modes: [:direct] do |r|
    info = r.cluster(:info)
    slots = r.cluster(:slots)
    [
      info.class, info["cluster_state"], slots.class, slots.size, r.cluster(:keyslot, "k"), r.cluster(:myid).class,
      r.cluster(:countkeysinslot, 0), r.cluster(:getkeysinslot, 0, 10), r.cluster(:nodes).map(&:keys).sort, r.cluster(:shards).size, r.asking
    ]
  end

  conform "cluster on a standalone server", targets: [:standalone], raises: true do |r|
    r.cluster(:info)
  end
end

RSpec.describe("Cluster pipelines") do
  # Commands Redis reports no fixed key position for (LMPOP, BLMPOP, ZMPOP, BZMPOP, ZINTER, ...) go to a random
  # node in redis-rb's cluster pipelines, and run after the rest whenever they're redirected; the data is set up
  # beforehand and each key is used once, so the order doesn't change the replies.
  conform "commands without a fixed key position", targets: [:cluster], modes: [:pipelined] do |r|
    Conformance.side.rpush("{l}a", ["1", "2", "3"])
    Conformance.side.rpush("{l}b", ["1", "2", "3"])
    Conformance.side.zadd("{z}a", [[1, "a"], [2, "b"]])
    Conformance.side.zadd("{z}b", [[1, "a"], [2, "b"]])
    Conformance.side.zadd("{z}c", [[2, "b"], [3, "c"]])
    [
      r.lmpop("{l}a", count: 2), r.blmpop(0.1, "{l}b", modifier: "RIGHT"), r.zmpop("{z}a", modifier: "MAX"), r.bzmpop(0.1, "{z}b"),
      r.zinter("{z}c", "{z}c"), r.zunion("{z}c", "{z}c", with_scores: true), r.zdiff("{z}c", "{z}c"), r.eval("return redis.call('GET', KEYS[1])", ["{l}x"])
    ]
  end

  conform "keys on several nodes, in order per node", targets: [:cluster], modes: [:pipelined] do |r|
    [r.set("a", "1"), r.set("b", "1"), r.incr("a"), r.incr("b"), r.get("a"), r.get("b"), r.del("a"), r.exists?("a")]
  end
end
