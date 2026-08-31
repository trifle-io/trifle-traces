# Trifle::Traces

[![Gem Version](https://badge.fury.io/rb/trifle-traces.svg)](https://rubygems.org/gems/trifle-traces)
[![Ruby](https://github.com/trifle-io/trifle-traces/workflows/Ruby/badge.svg?branch=main)](https://github.com/trifle-io/trifle-traces)

Structured execution tracing for Ruby. Track timestamped outputs from background jobs, API integrations, and anything else that runs in a black box. Know exactly what happened, when, and in what order.

Part of the [Trifle](https://trifle.io) ecosystem.

Also available as [Trifle.Traces for Elixir](https://github.com/trifle-io/trifle_traces),
with the same 2.0 persistence format.

## Quick Start

```ruby
gem 'trifle-traces'
```

```ruby
Trifle::Traces.tracer = Trifle::Traces::Tracer::Hash.new(key: 'jobs/sync')

Trifle::Traces.trace('Starting sync')
result = Trifle::Traces.trace('Fetching records from API') { api.fetch_all }
Trifle::Traces.trace('Sync complete')

Trifle::Traces.tracer.wrapup
```

Every message becomes a structured timeline entry on the tracer:

```ruby
Trifle::Traces.tracer.data
#=> [
#     {at: 1739700000, message: 'Starting sync', state: :success, type: :text, level: 0},
#     {at: 1739700001, message: 'Fetching records from API', state: :success, type: :text, level: 0},
#     {at: 1739700003, message: 'Sync complete', state: :success, type: :text, level: 0}
#   ]
```

Ideal for debugging those background-job-that-talks-to-API-and-works-every-time-when-you-run-it-manually-but-never-in-production type of jobs.

## Persistence (v2.0)

Traces persist through two pluggable drivers: an **index driver** (searchable
trace metadata) and a **data driver** (the payload). Configure both and the
gem handles the whole lifecycle — no hand-written persistence callbacks.

```ruby
Trifle::Traces.configure do |config|
  config.index_driver = Trifle::Traces::Driver::Index::Mongo.new(
    mongo_client, collection_name: 'trifle_traces'
  )
  config.data_driver = Trifle::Traces::Driver::Data::S3.new(
    client: s3_client, buckets: %w[traces-a traces-b], gzip: true
  )

  config.context   = ->(tracer) { { tenant_id: tracer.meta&.first } } # extra index fields
  config.retention = ->(tracer) { 3 }                                 # days, value or callable
end
```

- **Index drivers:** `Postgres` (shared schema with the Elixir implementation), `Mongo` (production-proven at 100M+ traces/day), `Memory`, `Null`. ClickHouse/OpenSearch are planned — see `lib/trifle/traces/driver/README.md` to write your own.
- **Data drivers:** `S3` (any S3-compatible storage, multi-bucket sharding, gzip), `File`, `Memory`, `Null`.
- **Retention:** carried on every record (`retention` days + `expires_at`). Mongo expires metadata via TTL index; Postgres provides `cleanup!` for a scheduled job; S3 expires payloads via one lifecycle rule per retention class (`Driver::Data::S3.setup!` creates them).
- Without configured drivers nothing persists — data stays on the tracer for your callbacks, as in 1.x.

Postgres keeps the client injectable, so the gem still has no runtime
dependencies. Add `pg` to the host application, provision the table once, and
schedule cleanup for expired metadata:

```ruby
require 'pg'

client = PG.connect(ENV.fetch('DATABASE_URL'))
Trifle::Traces::Driver::Index::Postgres.setup!(client)

Trifle::Traces.configure do |config|
  config.index_driver = Trifle::Traces::Driver::Index::Postgres.new(client)
end

# Run periodically from your scheduler:
Trifle::Traces.default.index_driver.cleanup!
```

### Write modes

Every liftoff/bump/wrapup writes to the index in `:live` mode (default),
giving you live progress. For fast, line-heavy, high-volume jobs use
`:deferred` — zero I/O until wrapup, then exactly one index write and one
payload part per trace:

```ruby
class Commodity::PollJob
  include Sidekiq::Job
  sidekiq_options tracer_key: 'commodity/poll', tracer_mode: :deferred
end
```

### Reading traces back

```ruby
record = Trifle::Traces.find(reference) #=> TraceRecord with duration and counters
result = Trifle::Traces.search(
  segment: 'jobs/sync',
  tags: { any: ['tenant:42', 'tenant:43'], all: ['failed'] },
  state: :error,
  from: Time.utc(2026, 8, 30),
  to: Time.utc(2026, 8, 31),
  duration_min: 5_000,
  limit: 50,
  cursor: nil
)
entries = Trifle::Traces.payload(record) # all parts, in order
```

`duration` is elapsed monotonic time in integer milliseconds. `counters`
contains totals by entry state and type plus `max_level`. Search selects traces
that started in the half-open interval `first_at >= from` and `first_at < to`;
`duration_min` is inclusive. Tag groups mean `(any[0] OR any[1] ...) AND
all[0] AND all[1] ...`; empty groups are ignored.

Search is intentionally narrow — materialized key-path segment, explicit tag
groups, exact state, start-time range and minimum duration, newest-first with
opaque cursor pagination. That is what stays fast at hundreds of millions of
traces.

### Callbacks

Callbacks still fire on `:liftoff`, `:bump` and `:wrapup` — use them for
side effects like emitting metrics (persistence no longer belongs here):

```ruby
Trifle::Traces.configure do |config|
  config.on(:wrapup) do |tracer|
    tracer.keys.each do |key|
      Trifle::Stats.track(key: "traces::#{key}", at: Time.now, values: { count: 1 })
    end
  end
end
```

### Upgrading from 1.x

- The return value of `:liftoff` callbacks no longer becomes `tracer.reference` — the index driver generates references. Move persistence out of callbacks into drivers (or implement a custom driver; see `lib/trifle/traces/driver/README.md`).
- Persistence errors are no longer silent: liftoff/wrapup failures raise, bump failures re-queue the data and retry on the next flush. Override `config.error_handler` to customize.

## Features

- **Simple tracing.** Collect messages and return values from code execution.
- **Driver-based persistence.** Postgres or Mongo metadata + S3/File payloads out of the box; contracts for custom backends.
- **Deferred mode.** One write per trace for high-volume jobs (100M/day proven).
- **State management.** Automatic success/error state tracking.
- **Callbacks.** Hook into trace events for custom processing.
- **Middleware integration.** Built-in support for Rack, Rails, and Sidekiq.
- **Thread-safe.** Safe for concurrent execution.
- **Zero runtime dependencies.** Database/storage clients are injected.

## Middleware

Trifle::Traces provides middleware for popular frameworks:

- **Rack.** HTTP request tracing.
- **Rails.** Controller and view tracing.
- **Sidekiq.** Background job tracing (`sidekiq_options tracer_key:, tracer_mode:`).

## Documentation

Full guides and API reference at **[docs.trifle.io/trifle-traces](https://docs.trifle.io/trifle-traces)**

## Trifle Ecosystem

| Component | What it does |
|-----------|-------------|
| **[Trifle App](https://trifle.io/product/app)** | Dashboards, alerts, scheduled reports, AI-powered chat. |
| **[Trifle::Stats](https://github.com/trifle-io/trifle-stats)** | Time-series metrics for Ruby (Postgres, Redis, MongoDB, MySQL, SQLite). |
| **[Trifle.Traces (Elixir)](https://github.com/trifle-io/trifle_traces)** | Elixir implementation with compatible Postgres, Mongo, and File/S3 persistence. |
| **[Trifle CLI](https://github.com/trifle-io/trifle-cli)** | Terminal access to metrics. MCP server mode for AI agents. |
| **[Trifle::Logs](https://github.com/trifle-io/trifle-logs)** | File-based log storage with ripgrep-powered search. |
| **[Trifle::Docs](https://github.com/trifle-io/trifle-docs)** | Map a folder of Markdown files to documentation URLs. |

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/trifle-io/trifle-traces.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
