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
commands sent to every node) run in a fiber per node.

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
| `tags:` | | Labels for async-pool's pools, e.g. for metrics, alongside the server's URL (`endpoint:`) |

On a cluster with an async pool, `concurrency:` defaults to `{ model: :async }`, redis-async-pool's fiber
worker; redis-cluster-client's own models (`:none`, `:on_demand`, `:pooled`) still work.

A `watch` block sends its fiber's commands over one connection, as WATCH requires (on a cluster,
redis-cluster-client already does), and UNWATCHes it before it goes back to the pool: one more round trip
than redis-rb's. Pools are re-entrant like connection_pool's: a fiber that holds a connection gets the
same one again; the fibers it starts get their own.

A checkout that waits longer than `timeout:` raises `Redis::ConnectionError`, with either kind of pool.
An async pool also works outside a reactor (each checkout runs in one of its own), but isn't thread-safe.

## How it works

- `Client` and `ClusterClient` subclass `Redis` and `Redis::Cluster`, replacing their client (one
  redis-client connection, or redis-cluster-client without pools) with a pooled one, and the lock around it.
- `pool: { async: true }` makes redis-client's `RedisClient::Pooled` (which redis-cluster-client also
  uses for each node) build its pool with `Connections`: async-pool's `Async::Pool::Controller` behind
  connection_pool's interface.
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

## Performance

[bench/](bench/README.md) compares it with redis-rb in a `ConnectionPool::Wrapper`. On a laptop, with
Redis in Docker: on a standalone server they're within a few percent; on a three-node cluster,
redis-async-pool does about 20% more operations per second for 10–20% less CPU per operation under
concurrency, up to 65% more for `mget` and pipelines across nodes, and removes multi-second p99s that a
`ConnectionPool::Wrapper` of `Redis::Cluster`s shows with 256 fibers.

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
