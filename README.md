# redis-async-pool

[redis-rb](https://github.com/redis/redis-rb) for [Async](https://github.com/socketry/async) and
[Falcon](https://github.com/socketry/falcon): one client shared by every fiber, over connection pools.

redis-rb works under Async: redis-client's sockets go through the fiber scheduler. But a `Redis` (or
`Redis::Cluster`) serializes every command on one connection, so fibers sharing one wait for each other,
and the usual fix, a `ConnectionPool` of clients, checks a whole client out for each call: on a cluster,
that's a connection to every node, for one fiber at a time, and redis-cluster-client sends a command's
share to each node one after another.

redis-async-pool's clients are redis-rb's own `Redis` and `Redis::Cluster`, without the serialization,
over connection pools that every fiber shares: one pool on a standalone server, one per node on a
cluster. They're [async-pool](https://github.com/socketry/async-pool)'s pools (or connection_pool's, for
threads), and on a cluster, commands that reach several nodes (pipelines, `mget`, `mset`, `del`,
commands sent to every node) run in a fiber per node. When every connection is busy, the commands of the
fibers waiting for one go out together, in one pipeline per connection (auto-pipelining).

Every method, reply transformation, pipeline, future, transaction, subscription and error is redis-rb's
(and redis-cluster-client's) own code, so code written for redis-rb runs unchanged.

## Installation

```ruby
# Gemfile
gem "redis-async-pool", require: "redis/async/pool"
```

## Usage

The clients take redis-rb's options, and `pool:`.

```ruby
require "redis/async/pool"

redis = Redis::Async::Pool::Client.new(url: "redis://localhost:6379", pool: { size: 16 })
cluster = Redis::Async::Pool::ClusterClient.new(nodes: ["redis://node-1:6379"], pool: { size: 16 })

Sync do
  barrier = Async::Barrier.new
  100.times { |i| barrier.async { redis.incr("counter:#{i % 10}") } }
  barrier.wait
end
```

| `pool:` option | Default | |
|---|---|---|
| `size:` | 5 | Connections (per node, on a cluster) |
| `timeout:` | 5 | Seconds a checkout waits for a free connection before raising `Redis::ConnectionError` |
| `async:` | `true` | async-pool's pools (fibers only); `false` uses connection_pool's (threads too) |
| `auto_pipeline:` | `true` | With async-pool's pools, sends the single commands of fibers that find every connection busy in one pipeline |
| `tags:` | | Labels for async-pool's pools, e.g. for metrics, alongside the server's URL (`endpoint:`) |

On a cluster with an async pool, `concurrency:` defaults to `{ model: :async }`, redis-async-pool's fiber
worker; redis-cluster-client's own models (`:none`, `:on_demand`, `:pooled`) still work.

A `watch` block sends its fiber's commands over one connection, as WATCH requires (on a cluster,
redis-cluster-client already does), and UNWATCHes it before it goes back to the pool: one more round trip
than redis-rb's. Pools are re-entrant like connection_pool's: a fiber that holds a connection gets the
same one again; the fibers it starts get their own.

A checkout that waits longer than `timeout:` raises `Redis::ConnectionError`, with either kind of pool.
An async pool also works outside a reactor (each checkout runs in one of its own), but isn't thread-safe.

### Auto-pipelining

A single command (anything but `pipelined`, `multi` and a `watch` block's commands) takes a free
connection if there is one, as it would without auto-pipelining. If every connection is busy, it queues:
the first fiber to queue waits for a connection, in line with the fibers checking connections out, and
sends every command queued by then in one pipeline. Each fiber gets its own reply, error or reply block's
result, so callers can't tell, except that under load the round trips, reads and writes of many commands
become one. Commands that change or block the connection they run on (`multi`, `watch`, `select`, `auth`,
`hello`, `client`, `reset`, `wait`, `waitaof`, subscriptions, blocking pops, `xread`, ...) always go
alone.

On a cluster, each node's share of a `pipelined` block, or of a command split across nodes (`mget`,
`mset`, `del`, ...), queues the same way, alongside single commands, and comes back to redis-cluster-client
as if it had gone alone: it follows MOVED and ASK redirections in it as usual. A share with a blocking
command, or a command that mustn't be retried, goes alone.

What a batched command does differently:

- redis-client middlewares (e.g. instrumentation) see one `call_pipelined` with every fiber's commands,
  run in the fiber that sends it, rather than a `call` per command in its own fiber.
- If the connection fails, every command in the pipeline fails with its error (redis-client retries a
  pipeline as it would a command). The pipeline goes out in a task of its own, so stopping or timing out
  the fiber that sent it doesn't fail the others; a fiber that stops or times out after its command went
  out (as with a single command) leaves the command to run, and one that stops while queued just leaves
  the queue.

`pool: { auto_pipeline: false }` sends every command over a connection of its own.

## How it works

- `Client` and `ClusterClient` subclass `Redis` and `Redis::Cluster`, replacing their client (one
  redis-client connection, or redis-cluster-client without pools) with a pooled one, and the lock around it.
- `pool: { async: true }` makes redis-client's `RedisClient::Pooled` (which redis-cluster-client also
  uses for each node) build its pool with `Connections`: async-pool's `Async::Pool::Controller` behind
  connection_pool's interface, which also auto-pipelines the single commands `RedisClient::Pooled` sends,
  and (through `ClusterPipelining`, prepended to redis-cluster-client's pipeline) a cluster node's share of
  a pipeline.
- `concurrency: { model: :async }` makes redis-cluster-client use `FiberWorker`.

Both are hooks prepended to redis-client and redis-cluster-client on load, inert unless a client asks for
them. Loading the gem checks that redis-rb, redis-client, redis-cluster-client and async-pool still have
the internals it builds on, and raises `Redis::Async::Pool::IncompatibleError` (naming what's missing) if
not.

## Differences from redis-rb

The conformance specs (`spec/conformance/`) run every redis-rb command, and the client API around them,
through redis-rb and redis-async-pool (with each kind of pool), on a standalone server and a three-node
cluster, called directly and inside `pipelined` and `multi`, and require the same return values and
errors. A coverage spec fails if a redis-rb method has no case. They pass with no known gaps; a case that
starts failing can be listed in [`spec/conformance/known_gaps.yml`](spec/conformance/known_gaps.yml),
where it runs as pending until fixed (`CONFORMANCE_GAPS=off` runs those cases normally).

redis-rb's own lint tests (`test/lint/`, vendored from redis-rb) also run against it, with each kind of
pool: the replies redis-rb's maintainers expect.

Where it differs by design, sharing a client across fibers changes what some state covers:
`subscribed?` and redis-rb's one-subscription-at-a-time rule apply to the whole client, and a `watch`
without a block (followed by `multi`) can't know which pooled connection the `multi` will use, so use
the block form.

Server state that belongs to a connection covers whichever pooled connection a command runs on, which
isn't always the one the fiber's previous command used (it is when the pool isn't busy): `wait` and `waitaof` count
only that connection's writes, and an HIMPORT fieldset exists only on the connection that prepared it. redis-rb
re-prepares a fieldset when `himport_set` finds it missing, so sets work, but `himport_discard` and
`himport_discard_all` only discard it on the connection they run on.

## Performance

[bench/](bench/README.md) compares it with redis-rb in a `ConnectionPool::Wrapper`. In a Linux container
next to Redis, with 4 connections (operations per second, and CPU per operation):

| | 1 fiber | 64 fibers | 256 fibers |
|---|---|---|---|
| standalone `get` | 47k vs 45k | 270k vs 37k (3.1 vs 27 µs) | 345k vs 13k (2.5 vs 79 µs) |
| standalone `hgetall` | 37k vs 36k | 108k vs 31k | 127k vs 12k |
| cluster `get` | 48k vs 46k | 172k vs 31k (5.8 vs 32 µs) | 245k vs 11k |
| cluster `mget` (10 keys across nodes) | 9.5k vs 7.2k | 20.6k vs 9.3k (48 vs 107 µs) | 21.0k vs 3.6k |
| cluster `pipelined` (10 GETs across nodes) | 8.7k vs 7.1k | 17.3k vs 8.5k | 16.3k vs 3.4k |
| cluster `fanout` (5 fibers' GETs) | 7.6k vs 7.1k | 15.7k vs 4.5k | 14.7k vs 1.9k |

With one fiber it's within noise of redis-rb, and on a cluster its fan-out cuts the latency of commands
across nodes by about a quarter. Under concurrency, auto-pipelining turns the round trips of many fibers' commands into one,
and a `ConnectionPool::Wrapper` of `Redis::Cluster`s shows multi-second p99s at 256 fibers that it doesn't.

Every Async task runs in a fiber, and Ruby releases a finished fiber's stack to the OS, so the next
fiber's stack faults its pages back in. `RUBY_SHARED_FIBER_POOL_FREE_STACKS=0` keeps them, for less CPU
per fiber (on a cluster, about 18% less per `fanout` and 11% per cross-node pipeline) at the cost of
keeping the stacks of the most fibers alive at once in memory.

## Development

The specs flush the Redis servers they run against, so they use disposable ones and refuse to start on a
server that has data:

```bash
docker compose up -d   # standalone on 6390, a three-node cluster on 6391-6393
bundle exec rspec      # POOL=connection_pool runs the conformance specs over connection_pool
bundle exec rake lint  # redis-rb's lint tests (database 15 of the standalone server); POOL= too
bundle exec rubocop
```

`REDIS_URL` and `REDIS_CLUSTER_URL` point the specs elsewhere.
