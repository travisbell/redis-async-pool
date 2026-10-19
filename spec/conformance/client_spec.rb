# frozen_string_literal: true

# The client's own API: transactions, pipelines, raw commands and connection handling.
RSpec.describe("Client") do
  conform "multi", modes: [:direct] do |r|
    multi = r.multi do |t|
      t.set("k", "1")
      t.incr("k")
      t.hgetall("missing")
      t.sismember("s", "a")
    end
    [multi, r.multi { |_t| nil }]
  end

  conform "multi with futures", modes: [:direct] do |r|
    futures = []
    result = r.multi do |t|
      t.set("{k}a", "1")
      futures << t.incr("{k}a") << t.hgetall("{k}h") << t.exists?("{k}a")
    end
    [result, futures.map(&:value)]
  end

  conform "multi with an error", modes: [:direct], raises: true do |r|
    r.multi do |t|
      t.set("k", "x")
      t.incr("k")
      t.set("k", "y")
    end
  end

  conform "multi with an error leaves the earlier commands applied", modes: [:direct] do |r|
    r.multi do |t|
      t.set("k", "x")
      t.incr("k")
    end
  rescue Redis::CommandError
    r.get("k")
  end

  conform "pipelined", modes: [:direct] do |r|
    pipelined = r.pipelined do |p|
      p.set("k", "1")
      p.incr("k")
      p.hgetall("missing")
      p.sismember("s", "a")
    end
    [pipelined, r.pipelined { |_p| nil }]
  end

  conform "pipelined with futures", modes: [:direct] do |r|
    futures = []
    result = r.pipelined do |p|
      p.set("a", "1")
      futures << p.incr("a") << p.hgetall("h") << p.exists?("a") << p.get("b")
    end
    [result, futures.map(&:value)]
  end

  conform "pipelined with an error", modes: [:direct], raises: true do |r|
    r.pipelined do |p|
      p.set("k", "x")
      p.incr("k")
      p.set("k", "y")
    end
  end

  conform "pipelined with an error runs every command", modes: [:direct] do |r|
    r.pipelined do |p|
      p.set("k", "x")
      p.incr("k")
      p.set("k", "y")
    end
  rescue Redis::CommandError
    [r.get("k"), r.ping]
  end

  conform "pipelined(exception: false)", modes: [:direct] do |r|
    r.pipelined(exception: false) do |p|
      p.set("k", "x")
      p.incr("k")
      p.get("k")
    end
  end

  conform "a future's value before the pipeline runs", modes: [:direct], raises: true do |r|
    r.pipelined { |p| p.get("k").value }
  end

  conform "multi inside pipelined", targets: [:standalone], modes: [:direct] do |r|
    r.pipelined do |p|
      p.set("k", "1")
      p.multi do |t|
        t.incr("k")
        t.incr("k")
      end
      p.get("k")
    end
  end

  # The WATCH that redis-rb sends from a pipeline goes out as a CALL_V command with no key, so both clients
  # send it to a random cluster node, which the error names.
  conform "watch and unwatch", except: ["cluster/pipelined"] do |r|
    [r.set("{k}a", "1"), r.watch("{k}a"), r.unwatch]
  end

  conform "watch with an unchanged key", modes: [:direct] do |r|
    r.set("k", "1")
    result = r.watch("k") do |c|
      c.multi { |t| t.set("k", "2") }
    end
    [result, r.get("k")]
  end

  conform "watch with a key changed by another client", modes: [:direct] do |r|
    r.set("k", "1")
    result = r.watch("k") do |c|
      Conformance.side.set("k", "changed")
      c.multi { |t| t.set("k", "2") }
    end
    [result, r.get("k")]
  end

  conform "watch, then unwatch", modes: [:direct] do |r|
    r.set("k", "1")
    result = r.watch("k") do |c|
      Conformance.side.set("k", "changed")
      c.unwatch
      c.multi { |t| t.set("k", "2") }
    end
    [result, r.get("k")]
  end

  # Pipelines route by key alone, so DISCARD goes to a random cluster node in both clients.
  conform "exec and discard outside multi", except: ["cluster/pipelined"], raises: true do |r|
    r.discard
  rescue Redis::CommandError => error
    [error.message, r.exec]
  end

  conform "call" do |r|
    [r.call("SET", "k", "v"), r.call(:get, "k"), r.call("HSET", "h", "a", "1"), r.call("HGETALL", "h"), r.call(["SADD", "s", "x"])]
  end

  conform "call with an error", raises: true do |r|
    [r.call("SET", "k", "x"), r.call("INCR", "k")]
  end

  conform "commands redis-rb has no method for" do |r|
    # covers: method_missing
    [r.rpush("l", ["a", "b"]), r.lpos("l", "b"), r.lpos("l", "b", rank: -1)]
  end

  conform "with", modes: [:direct] do |r|
    r.with { |c| [c.set("k", "v"), c.get("k")] }
  end

  conform "connected?, close and disconnect!", modes: [:direct] do |r|
    [r.connected?, r.ping, r.connected?, r.close, r.connected?, r.ping, r.disconnect!, r.connected?]
  end

  conform "id", modes: [:direct] do |r|
    r.id
  end

  conform "connection", modes: [:direct] do |r|
    r.connection
  end

  conform "without_reconnect", modes: [:direct] do |r|
    r.without_reconnect { r.ping }
  end
end
