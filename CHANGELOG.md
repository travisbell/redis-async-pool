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
- Conformance specs comparing it with redis-rb, a coverage spec, concurrency specs and a benchmark.
