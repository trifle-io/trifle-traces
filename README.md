# Trifle::Logger

[![Gem Version](https://badge.fury.io/rb/trifle-logger.svg)](https://badge.fury.io/rb/trifle-logger)
![Ruby](https://github.com/trifle-io/trifle-logger/workflows/Ruby/badge.svg?branch=main)
[![Gitpod ready-to-code](https://img.shields.io/badge/Gitpod-ready--to--code-blue?logo=gitpod)](https://gitpod.io/#https://github.com/trifle-io/trifle-logger)


Simple logger backed by Redis, Postgres, MongoDB, or whatever.

`Trifle::Logger` is a way too simple timeline logger that helps you track custom outputs. Ideal for any code from blackbox category (aka background-job-that-talks-to-API-and-works-every-time-when-you-run-it-manually-but-never-when-in-production type of jobs)

## Documentation

You can find guides and documentation at https://trifle.io/trifle-logger

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'trifle-logger'
```

And then execute:

    $ bundle install

Or install it yourself as:

    $ gem install trifle-logger

## Usage

It saves you from reading through your standard logger

```ruby
Trifle::Logger.trace('This is important output')
now = Trifle::Logger.trace('And it\'s important to know it happened at') do
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

Bug reports and pull requests are welcome on GitHub at https://github.com/trifle-io/trifle-logger.
