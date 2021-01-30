# frozen_string_literal: true

require 'trifle/logger/configuration'
require 'trifle/logger/tracer/hash'
require 'trifle/logger/tracer/null'
require 'trifle/logger/version'

module Trifle
  module Logger
    class Error < StandardError; end
    # Your code goes here...

    def self.default
      @default ||= Configuration.new
    end

    def self.configure
      yield(default)

      default
    end

    def self.tracer=(tracer)
      Thread.current[:trifle_tracer] = tracer
    end

    def self.tracer
      Thread.current[:trifle_tracer] ||= Trifle::Logger::Tracer::Null.new
    end

    def self.trace(*args, **keywords, &block)
      tracer.trace(*args, **keywords, &block)
    end
  end
end
