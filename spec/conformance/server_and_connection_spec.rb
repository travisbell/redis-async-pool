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

  conform "info with several sections", modes: [:direct] do |r|
    several = r.info("server", "clients")
    listed = r.info(["memory", :keyspace])
    [several.class, several.key?("redis_version"), several.key?("connected_clients"), several.key?("used_memory"), listed.key?("used_memory"), r.info(:everything).key?("cmdstat_info")]
  end

  # With appendonly off (as on the specs' servers) WAITAOF can only wait for no local fsync.
  conform "waitaof" do |r|
    [r.set("k", "v"), r.waitaof(0, 0, 0), r.waitaof(0, 0, 100)]
  end

  conform "waitaof with appendonly off", targets: [:standalone], raises: true do |r|
    r.waitaof(1, 0, 0)
  end

  # HOTKEYS tracks a server-wide session that survives the harness's flush, so each case first ends any left over.
  conform "hotkeys", targets: [:standalone] do |r|
    Conformance.side.then { |side| [side.hotkeys_stop, side.hotkeys_reset] }
    [
      r.hotkeys_get, r.hotkeys_stop, r.hotkeys_start(metrics: [:cpu, :net], count: 5, sample: 1), r.hotkeys_stop, r.hotkeys_stop,
      r.hotkeys_reset, r.hotkeys_get, r.hotkeys_start(metrics: "net", duration: 60), r.hotkeys_stop, r.hotkeys_reset
    ]
  end

  # A session's counters and timings differ between runs (a key whose commands took under 1µs of CPU isn't
  # listed by CPU time), so only the shape, the hottest keys by bytes and the keys listed by CPU are compared.
  conform "hotkeys_get of a session", targets: [:standalone], modes: [:direct] do |r|
    Conformance.side.then { |side| [side.hotkeys_stop, side.hotkeys_reset] }
    r.hotkeys_start(metrics: [:cpu, :net], count: 2)
    r.set("hot", "x" * 1000)
    3.times { r.get("hot") }
    r.set("cold", "x")
    active = r.hotkeys_get
    stopped = [r.hotkeys_stop, r.hotkeys_get]
    [
      active.keys.sort, active.values_at("tracking-active", "sample-ratio", "selected-slots"), active["by-net-bytes"].map(&:first),
      (active["by-cpu-time-us"].map(&:first) - ["hot", "cold"]), stopped[0], stopped[1]["tracking-active"], r.hotkeys_reset
    ]
  end

  conform "hotkeys_start during a session", targets: [:standalone], raises: true do |r|
    Conformance.side.then { |side| [side.hotkeys_stop, side.hotkeys_reset] }
    [r.hotkeys_start(metrics: :cpu), r.hotkeys_start(metrics: :net)]
  end

  conform "hotkeys_reset during a session", targets: [:standalone], raises: true do |r|
    Conformance.side.then { |side| [side.hotkeys_stop, side.hotkeys_reset] }
    [r.hotkeys_start(metrics: :cpu), r.hotkeys_reset]
  end

  conform "hotkeys_start with slots on a standalone server", targets: [:standalone], raises: true do |r|
    Conformance.side.then { |side| [side.hotkeys_stop, side.hotkeys_reset] }
    r.hotkeys_start(metrics: :cpu, slots: [0])
  end

  # Redis::Cluster raises NotImplementedError for the HOTKEYS family, since the session is a single node's.
  conform "hotkeys on a cluster", targets: [:cluster], modes: [:direct] do |r|
    [-> { r.hotkeys_start(metrics: :cpu) }, -> { r.hotkeys_get }, -> { r.hotkeys_stop }, -> { r.hotkeys_reset }].map do |command|
      command.call
    rescue NotImplementedError => error
      [error.class, error.message]
    end
  end

  conform "hotkeys in a cluster pipeline or transaction", targets: [:cluster], modes: [:pipelined, :multi] do |r|
    [r.set("k", "v"), r.hotkeys_get]
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

  # Every primary reports its own slots, in an order that differs between runs; their CPU and network counters
  # differ too.
  conform "cluster slot-stats", targets: [:cluster], modes: [:direct] do |r|
    ["a", "b", "{a}c"].each { |key| r.set(key, "1") }
    all = r.cluster("slot-stats", "SLOTSRANGE", 0, 16_383)
    top = r.cluster("slot-stats", "ORDERBY", "key-count", "LIMIT", 1)
    [
      all.size, all.first.last.keys.sort, all.select { |_slot, stats| stats["key-count"].positive? }.sort.map { |slot, stats| [slot, stats["key-count"]] },
      top.map { |slot, stats| [slot, stats["key-count"]] }.sort, r.cluster(:"slot-stats", "SLOTSRANGE", 0, 0).map(&:first)
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

RSpec.describe("Keyspace notifications") do
  # The manager listens on its own connections (one per cluster node) and threads, so this runs directly.
  conform "keyspace_notifications", modes: [:direct] do |r|
    servers = Conformance.servers(r.is_a?(Redis::Cluster) ? :cluster : :standalone)
    servers.each { |server| server.config(:set, "notify-keyspace-events", "KEA") }
    received = Queue.new
    manager = r.keyspace_notifications
    manager.subscribe_keyevent("set") { |notification| received << notification }
    manager.subscribe_keyspace("{k}*") { |notification| received << notification }
    r.set("{k}a", "1")
    r.del("{k}a")
    notifications = Array.new(3) { received.pop(timeout: 2) }
    [notifications.map { |notification| notification && [notification.family, notification.key, notification.event] }.sort, manager.subscribed?]
  ensure
    manager&.close
    servers&.each { |server| server.config(:set, "notify-keyspace-events", "") }
  end
end
