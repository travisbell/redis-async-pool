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
- `Redis::Async::Pool::Compatibility`: refuses to load against dependencies without the internals it builds on.
- Conformance specs comparing it with redis-rb, a coverage spec, concurrency specs and a benchmark.
