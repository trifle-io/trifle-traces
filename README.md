# Trifle::Traces

[![Gem Version](https://badge.fury.io/rb/trifle-traces.svg)](https://badge.fury.io/rb/trifle-traces)
![Ruby](https://github.com/trifle-io/trifle-traces/workflows/Ruby/badge.svg?branch=main)

Simple tracer backed by Redis, Postgres, MongoDB, or whatever.

`Trifle::Traces` is a way too simple timeline tracer that helps you track custom outputs. Ideal for any code from blackbox category (aka background-job-that-talks-to-API-and-works-every-time-when-you-run-it-manually-but-never-when-in-production type of jobs)

## Documentation

You can find guides and documentation at https://trifle.io/trifle-traces

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'trifle-traces'
```

And then execute:

    $ bundle install

Or install it yourself as:

    $ gem install trifle-traces

## Usage

It saves you from reading through your standard traces

```ruby
Trifle::Traces.trace('This is important output')
now = Trifle::Traces.trace('And it\'s important to know it happened at') do
  Time.now
end
```

To being able to say what happened on 25th January 2021.

```ruby
[
  {at: 2021-01-25 00:00:00 +0100, message: 'This is important output', state: :success, head: false, meta: false}
  {at: 2021-01-25 00:00:00 +0100, message: 'And it\'s important to know it happened ', state: :success, head: false, meta: false}
  {at: 2021-01-25 00:00:00 +0100, message: '=> 2021-01-25 00:00:00 +0100', state: :success, head: false, meta: true}
]
```

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/trifle-io/trifle-traces.
