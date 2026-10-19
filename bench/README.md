# Benchmarks

Compares Redis clients the way Falcon runs them, in fibers on one Async reactor:

| Subject | What it is |
|---|---|
| `redis-rb` | redis-rb (`Redis`, `Redis::Cluster`) in a `ConnectionPool::Wrapper`: what code written for redis-rb uses under threads, a client checked out per call |
| `async-pool` | redis-async-pool over async-pool's pools, with fiber fan-out on the cluster |
| `connection_pool` | redis-async-pool over connection_pool's pools |

```bash
docker compose up -d
bundle exec ruby bench/run.rb --watchdog 90   # ~35 minutes
bundle exec ruby bench/run.rb --quick
bundle exec ruby bench/run.rb --targets cluster --scenarios mget --concurrency 1,64 --pools 4
```

It seeds and then flushes the disposable servers from docker-compose.yml. `--watchdog SECONDS` prints
every fiber's backtrace and exits if a step makes no progress for that long.

## Targets

| Target | Server |
|---|---|
| `standalone` | the standalone server, on localhost |
| `remote` | the same through [latency_proxy.rb](latency_proxy.rb), which delays its replies by `--latency-ms` (default 1ms), as a server farther away would |
| `cluster` | the three-node cluster (no added latency: its nodes announce their own addresses, which a proxy can't stand in for) |

## Scenarios

| Scenario | Each operation |
|---|---|
| `get` | a GET of a 100-byte value |
| `set` | a SET of a 100-byte value |
| `hgetall` | an HGETALL of a 20-field hash |
| `pipeline` | a pipeline of 10 GETs (across nodes on the cluster) |
| `mget` | an MGET of 10 keys (split across nodes on the cluster) |
| `fanout` | 5 GETs from 5 fibers at once |

Each measurement runs N fibers (`--concurrency`, default 1, 16, 64 and 256), each repeating the operation
until the time is up, with `--pools` connections (default 4 and 32). It reports operations/s, latency
percentiles, errors and the process's CPU time per operation.

## Fairness notes

- A pool's size means different things: `redis-rb` has that many clients, each with a connection to every
  cluster node and used by one fiber at a time; redis-async-pool has that many connections per node, each
  used by one command at a time. On a standalone server they're the same.
- Percentiles come from completed operations, so a fiber that waits the whole run for a connection adds
  no samples.
- The load runs in the same process and reactor as the client, so CPU per operation includes it equally.
- On a laptop, Redis (in Docker) is much closer than in production, which `remote` compensates for.
- YJIT is on.
