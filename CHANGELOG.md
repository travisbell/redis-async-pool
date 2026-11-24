# Changelog

## 0.1.0 (unreleased)

- `Redis::Async::Pool::Client` and `Redis::Async::Pool::ClusterClient`: redis-rb's `Redis` and
  `Redis::Cluster` over connection pools that fibers share, without redis-rb's lock around its one
  connection. A `watch` block's commands go over one connection.
- `pool: { async: true }` (the default): async-pool's pools behind connection_pool's interface
  (`Redis::Async::Pool::Connections`), re-entrant per fiber and tagged with the server's URL.
  `async: false` uses connection_pool's.
- `concurrency: { model: :async }` (the default on a cluster with an async pool): a redis-cluster-client
  concurrent worker that runs each node's share of a command in a fiber (`Redis::Async::Pool::FiberWorker`).
- Pools leave out async-pool's gardener, which woke on every release and closed the pool when its reactor
  finished (so outside a reactor every command reconnected), and only time checkouts that wait for a
  connection. About 15% less CPU per command.
- `FiberWorker` runs a group's last (or only) task in the calling fiber: 13–15% less CPU per cluster pipeline.
- `Redis::Async::Pool::Compatibility`: refuses to load against dependencies without the internals it builds on.
- Requires redis-rb 6.1 and redis-clustering 6.1, and speaks RESP3 unless given `protocol: 2`. Unlike redis-rb, it
  doesn't fall back to RESP2 by itself when a server rejects `HELLO 3` (Redis < 6).
- `ClusterClient` routes commands as redis-clustering does (e.g. `waitaof` to every primary), with the caller's
  `command_routings:` on top. `dup` takes redis-rb's option overrides, which `keyspace_notifications` relies on.
- Conformance specs comparing it with redis-rb (on Redis 8.12), a coverage spec, concurrency specs and a benchmark.
- Auto-pipelining (`pool: { auto_pipeline: true }`, the default with async-pool's pools): single commands that
  find every connection busy go out together, one pipeline per connection, each fiber getting its own reply. In a
  Linux container with 4 connections and 64–256 fibers, 3–30× the operations per second of redis-rb in a
  `ConnectionPool::Wrapper`, at 2–9 µs of CPU per command.
- On a cluster, auto-pipelining also takes in each node's share of a pipeline, or of a command split across nodes
  (`mget`, `mset`, `del`, ...): with 64–256 fibers, about twice the `mget`s and pipelines per second, for half the
  CPU and a tenth of the p99 latency.
- A checkout no longer takes a timeout around the caller's code (e.g. `task.with_timeout`) for its own, which
  raised `Redis::ConnectionError` instead of the caller's `Async::TimeoutError`, and doesn't time taking a
  connection the pool has room to open.
- Three fewer allocations per command (`Connections::Controller#available?`).
