# frozen_string_literal: true

require "digest/sha1"

RSpec.describe("Scripting") do
  script = "return {KEYS[1], ARGV[1], redis.call('INCR', KEYS[1])}"
  sha = Digest::SHA1.hexdigest(script)

  conform "eval and evalsha" do |r|
    [
      r.eval(script, ["k"], ["a"]), r.eval(script, keys: ["k"], argv: ["b"]), r.eval("return 1"), r.eval("return {1, 'two', nil, 3}"),
      r.script(:load, script), r.evalsha(sha, ["k"], ["c"]), r.evalsha(sha, keys: ["k"], argv: ["d"])
    ]
  end

  conform "script exists, load and flush" do |r|
    [r.script(:exists, sha), r.script(:exists, [sha, "0" * 40]), r.script(:load, script), r.script(:exists, sha), r.script(:flush), r.script(:exists, sha)]
  end

  conform "evalsha of an unknown script", raises: true do |r|
    r.evalsha("0" * 40, ["k"])
  end

  conform "eval of a script that errors", raises: true do |r|
    [r.eval("return redis.call('INCR', KEYS[1])", ["k"]), r.set("k", "x"), r.eval("return redis.call('INCR', KEYS[1])", ["k"])]
  end

  conform "eval returning an error reply", raises: true do |r|
    r.eval("return redis.error_reply('MYERR custom')", ["k"])
  end
end

RSpec.describe("Functions") do
  library = <<~LUA
    #!lua name=conformance
    redis.register_function('incr_by', function(keys, args) return redis.call('INCRBY', keys[1], args[1]) end)
    redis.register_function{function_name='get', callback=function(keys) return redis.call('GET', keys[1]) end, flags={'no-writes'}}
    redis.register_function('echo', function(keys, args) return {#keys, args[1]} end)
  LUA
  other = "#!lua name=other\nredis.register_function('one', function() return 1 end)"
  third = "#!lua name=third\nredis.register_function{function_name='two', callback=function() return 2 end, flags={'no-writes'}}"

  # Functions survive the harness's flush, so each case starts by flushing them (on every cluster primary),
  # through the side client since a pipeline or transaction would run it only after the case's commands.
  # Libraries, and a library's functions, are listed in an order that differs between cluster nodes, so a
  # listing shows one library of one function.
  conform "function load, list, delete and flush" do |r|
    Conformance.side.function(:flush)
    [
      r.function(:load, third), r.function(:list), r.function(:load, other), r.function(:list, libraryname: "th*"),
      r.function(:list, libraryname: "other", withcode: true), r.function(:load, other, replace: true), r.function(:delete, "other"),
      r.function(:list), r.function(:flush), r.function(:list)
    ]
  end

  # Pipelines route by key alone, so this goes to a random cluster node in both clients, which the error names.
  conform "function load of an existing library", except: ["cluster/pipelined"], raises: true do |r|
    Conformance.side.function(:flush)
    [r.function(:load, other), r.function(:load, other)]
  end

  # Pipelines route by key alone, so this goes to a random cluster node in both clients, which the error names.
  conform "function delete of a missing library", except: ["cluster/pipelined"], raises: true do |r|
    Conformance.side.function(:flush)
    r.function(:delete, "missing")
  end

  conform "function dump, restore and stats" do |r|
    Conformance.side.function(:flush)
    Conformance.side.function(:load, other)
    payload = Conformance.side.function(:dump)
    Conformance.side.function(:flush)
    [
      r.function(:restore, payload), r.function(:list), r.function(:dump), r.function(:stats), r.function(:restore, payload, policy: :replace),
      r.function(:load, library), r.function(:restore, payload, policy: :flush), r.function(:list), r.function(:flush, "sync"), r.function(:stats)
    ]
  end

  # Pipelines route by key alone, so this goes to a random cluster node in both clients, which the error names.
  conform "function restore of a library that exists", except: ["cluster/pipelined"], raises: true do |r|
    Conformance.side.function(:flush)
    Conformance.side.function(:load, other)
    r.function(:restore, Conformance.side.function(:dump))
  end

  conform "fcall and fcall_ro" do |r|
    Conformance.side.function(:flush)
    Conformance.side.function(:load, library)
    [
      r.fcall("incr_by", ["{k}a"], ["2"]), r.fcall("incr_by", keys: ["{k}a"], argv: ["3"]), r.fcall_ro("get", ["{k}a"]), r.fcall_ro("get", keys: ["{k}b"]),
      r.fcall("echo", ["{k}a", "{k}b"], ["x"]), r.fcall("get", ["{k}a"]), r.function(:flush)
    ]
  end

  # FCALL has no fixed key position, so cluster pipelines send it to a random node and follow the redirection;
  # its error then comes back alone or in a CommandErrorCollection depending on the node reached.
  conform "fcall of a missing function", except: ["cluster/pipelined"], raises: true do |r|
    Conformance.side.function(:flush)
    r.fcall("missing", ["k"])
  end

  # FCALL_RO goes to a random node in cluster pipelines too (see above).
  conform "fcall_ro of a function that writes", except: ["cluster/pipelined"], raises: true do |r|
    Conformance.side.function(:flush)
    Conformance.side.function(:load, library)
    [r.set("k", "1"), r.fcall_ro("incr_by", ["k"], ["1"])]
  end
end

RSpec.describe("Pub/sub") do
  conform "publish, spublish and pubsub" do |r|
    [r.publish("c", "m"), r.spublish("c", "m"), r.pubsub(:channels), r.pubsub(:channels, "c*"), r.pubsub(:numsub, "c"), r.pubsub(:numpat), r.pubsub(:shardchannels)]
  end

  # Subscribing blocks until every channel is unsubscribed, so each case unsubscribes on its last message.
  conform "subscribe", targets: [:standalone], modes: [:direct] do |r|
    events = []
    r.subscribe("a", "b") do |on|
      on.subscribe do |channel, count|
        events << [:subscribe, channel, count, r.subscribed?]
        Conformance.side.publish(channel, "hello #{channel}") if count == 2
      end
      on.message do |channel, message|
        events << [:message, channel, message]
        Conformance.side.publish("b", "bye") if channel == "a"
        r.unsubscribe if channel == "b"
      end
      on.unsubscribe { |channel, count| events << [:unsubscribe, channel, count] }
    end
    events << [:after, r.subscribed?]
  end

  conform "psubscribe", targets: [:standalone], modes: [:direct] do |r|
    events = []
    r.psubscribe("news.*") do |on|
      on.psubscribe do |pattern, count|
        events << [:psubscribe, pattern, count]
        Conformance.side.publish("news.today", "hello")
      end
      on.pmessage do |pattern, channel, message|
        events << [:pmessage, pattern, channel, message]
        r.punsubscribe
      end
      on.punsubscribe { |pattern, count| events << [:punsubscribe, pattern, count] }
    end
    events
  end

  conform "ssubscribe", modes: [:direct] do |r|
    events = []
    r.ssubscribe("{c}a") do |on|
      on.ssubscribe do |channel, count|
        events << [:ssubscribe, channel, count]
        Conformance.side.spublish("{c}a", "hello")
      end
      on.smessage do |channel, message|
        events << [:smessage, channel, message]
        r.sunsubscribe
      end
      on.sunsubscribe { |channel, count| events << [:sunsubscribe, channel, count] }
    end
    events
  end

  conform "subscribe_with_timeout and psubscribe_with_timeout", targets: [:standalone], modes: [:direct] do |r|
    events = []
    r.subscribe_with_timeout(1, "a") do |on|
      on.subscribe { Conformance.side.publish("a", "hello") }
      on.message do |channel, message|
        events << [channel, message]
        r.unsubscribe("a")
      end
    end
    r.psubscribe_with_timeout(1, "a*") do |on|
      on.psubscribe { Conformance.side.publish("ab", "hello") }
      on.pmessage do |pattern, channel, message|
        events << [pattern, channel, message]
        r.punsubscribe("a*")
      end
    end
    r.ssubscribe_with_timeout(1, "{c}a") do |on|
      on.ssubscribe { Conformance.side.spublish("{c}a", "hello") }
      on.smessage do |channel, message|
        events << [channel, message]
        r.sunsubscribe("{c}a")
      end
    end
    events
  end

  conform "subscribe_with_timeout expiring", targets: [:standalone], modes: [:direct] do |r|
    r.subscribe_with_timeout(0.1, "a") { |on| on.message { nil } }
  end

  conform "unsubscribe outside a subscription", targets: [:standalone], modes: [:direct], raises: true do |r|
    r.unsubscribe("a")
  end
end
