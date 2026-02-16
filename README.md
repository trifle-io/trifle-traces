# Trifle::Traces

[![Gem Version](https://badge.fury.io/rb/trifle-traces.svg)](https://rubygems.org/gems/trifle-traces)
[![Ruby](https://github.com/trifle-io/trifle-traces/workflows/Ruby/badge.svg?branch=main)](https://github.com/trifle-io/trifle-traces)

Structured execution tracing for Ruby. Track timestamped outputs from background jobs, API integrations, and anything else that runs in a black box. Know exactly what happened, when, and in what order.

Part of the [Trifle](https://trifle.io) ecosystem.

## Quick Start

```ruby
gem 'trifle-traces'
```

```ruby
Trifle::Traces.trace('Starting sync')
result = Trifle::Traces.trace('Fetched 150 records from API') { api.fetch_all }
Trifle::Traces.trace('Sync complete')
```

Returns a structured timeline:

```ruby
Trifle::Traces.data
#=> [
#     {at: 2026-02-16 10:00:00, message: 'Starting sync', state: :success, head: false, meta: false},
#     {at: 2026-02-16 10:00:01, message: 'Fetched 150 records from API', state: :success, head: false, meta: false},
#     {at: 2026-02-16 10:00:03, message: 'Sync complete', state: :success, head: false, meta: false}
#   ]
```

Ideal for debugging those background-job-that-talks-to-API-and-works-every-time-when-you-run-it-manually-but-never-in-production type of jobs.

### Configure with callbacks

```ruby
Trifle::Traces.configure do |config|
  config.on(:success) { |trace| puts "Success: #{trace.message}" }
  config.on(:error) { |trace| puts "Error: #{trace.message}" }
end
```

## Features

- **Simple tracing** — Collect messages and return values from code execution
- **State management** — Automatic success/error state tracking
- **Callbacks** — Hook into trace events for custom processing
- **Middleware integration** — Built-in support for Rack, Rails, and Sidekiq
- **Thread-safe** — Safe for concurrent execution
- **Lightweight** — Minimal performance overhead

## Middleware

Trifle::Traces provides middleware for popular frameworks:

- **Rack** — HTTP request tracing
- **Rails** — Controller and view tracing
- **Sidekiq** — Background job tracing

## Documentation

Full guides and API reference at **[docs.trifle.io/trifle-traces](https://docs.trifle.io/trifle-traces)**

## Trifle Ecosystem

| Component | What it does |
|-----------|-------------|
| **[Trifle App](https://trifle.io/product-app)** | Dashboards, alerts, scheduled reports, AI-powered chat. |
| **[Trifle::Stats](https://github.com/trifle-io/trifle-stats)** | Time-series metrics for Ruby (Postgres, Redis, MongoDB, MySQL, SQLite). |
| **[Trifle CLI](https://github.com/trifle-io/trifle-cli)** | Terminal access to metrics. MCP server mode for AI agents. |
| **[Trifle::Logs](https://github.com/trifle-io/trifle-logs)** | File-based log storage with ripgrep-powered search. |
| **[Trifle::Docs](https://github.com/trifle-io/trifle-docs)** | Map a folder of Markdown files to documentation URLs. |

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/trifle-io/trifle-traces.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
