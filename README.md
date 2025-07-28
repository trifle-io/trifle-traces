# Trifle::Traces

[![Gem Version](https://badge.fury.io/rb/trifle-traces.svg)](https://rubygems.org/gems/trifle-traces)
[![Ruby](https://github.com/trifle-io/trifle-traces/workflows/Ruby/badge.svg?branch=main)](https://github.com/trifle-io/trifle-traces)

Simple log tracer that collects messages and values from your code and returns Hash. It saves you from reading through your standard logger to being able to say what happened during execution.

## Documentation

For comprehensive guides, API reference, and examples, visit [trifle.io/trifle-traces](https://trifle.io/trifle-traces)

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'trifle-traces'
```

And then execute:

```bash
$ bundle install
```

Or install it yourself as:

```bash
$ gem install trifle-traces
```

## Quick Start

### 1. Basic tracing

```ruby
require 'trifle/traces'

Trifle::Traces.trace('This is important output')
now = Trifle::Traces.trace('And it\'s important to know it happened at') do
  Time.now
end
```

### 2. Retrieve traces

```ruby
Trifle::Traces.data
#=> [
#     {at: 2021-01-25 00:00:00 +0100, message: 'This is important output', state: :success, head: false, meta: false},
#     {at: 2021-01-25 00:00:00 +0100, message: 'And it\'s important to know it happened at', state: :success, head: false, meta: false},
#     {at: 2021-01-25 00:00:00 +0100, message: '=> 2021-01-25 00:00:00 +0100', state: :success, head: false, meta: true}
#   ]
```

### 3. Configure with callbacks

```ruby
Trifle::Traces.configure do |config|
  config.on(:success) { |trace| puts "✅ #{trace.message}" }
  config.on(:error) { |trace| puts "❌ #{trace.message}" }
end
```

## Features

- **Simple tracing** - Collect messages and return values from code execution
- **State management** - Automatic success/error state tracking
- **Callbacks** - Hook into trace events for custom processing
- **Middleware integration** - Built-in support for Rack, Rails, and Sidekiq
- **Thread-safe** - Safe for concurrent execution
- **Lightweight** - Minimal performance overhead

## Middleware

Trifle::Traces provides middleware for popular frameworks:

- **Rack** - HTTP request tracing
- **Rails** - Controller and view tracing
- **Sidekiq** - Background job tracing

## Testing

Tests verify tracing behavior and middleware integration. To run the test suite:

```bash
$ bundle exec rspec
```

Tests are meant to be **simple and isolated**. Every test should be **independent** and able to run in any order. Tests should be **self-contained** and set up their own configuration.

Use **single layer testing** to focus on testing a specific class or module in isolation. Use **appropriate stubbing** for external dependencies when testing middleware components.

**Repeat yourself** in test setup for clarity rather than complex shared setups that can hide dependencies.

Tests verify that traces are properly collected, states are correctly managed, and callbacks are triggered as expected. Middleware tests ensure proper integration with web frameworks and background job processors.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/trifle-io/trifle-traces.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
