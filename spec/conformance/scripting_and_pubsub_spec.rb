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
