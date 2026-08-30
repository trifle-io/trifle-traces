# frozen_string_literal: true

require 'trifle/traces/ref'
require 'trifle/traces/trace_record'
require 'trifle/traces/configuration'
require 'trifle/traces/dispatcher'
require 'trifle/traces/driver/index/query'
require 'trifle/traces/driver/index/mongo'
require 'trifle/traces/driver/index/memory'
require 'trifle/traces/driver/index/null'
require 'trifle/traces/driver/data/s3'
require 'trifle/traces/driver/data/file'
require 'trifle/traces/driver/data/memory'
require 'trifle/traces/driver/data/null'
require 'trifle/traces/operations/trace/find'
require 'trifle/traces/operations/trace/search'
require 'trifle/traces/operations/trace/payload'
require 'trifle/traces/tracer/hash'
require 'trifle/traces/tracer/null'
require 'trifle/traces/serializer/inspect'
require 'trifle/traces/serializer/json'
require 'trifle/traces/serializer/string'
require 'trifle/traces/middleware/rack'
require 'trifle/traces/middleware/rails_controller'
require 'trifle/traces/middleware/sidekiq'
require 'trifle/traces/version'

module Trifle
  module Traces
    class Error < StandardError; end

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
      Thread.current[:trifle_tracer]
    end

    def self.trace(*args, **keywords, &block)
      if tracer.nil?
        return block_given? ? yield : nil
      end

      tracer.trace(*args, **keywords, &block)
    end

    def self.tag(tag)
      return unless tracer

      tracer.tag(tag)
    end

    def self.artifact(name, path)
      return unless tracer

      tracer.artifact(name, path)
    end

    def self.fail!
      return unless tracer

      tracer.fail!
    end

    def self.warn!
      return unless tracer

      tracer.warn!
    end

    def self.ignore!
      return unless tracer

      tracer.ignore!
    end

    def self.find(reference, config: nil)
      Trifle::Traces::Operations::Trace::Find.new(
        reference: reference, config: config
      ).perform
    end

    # rubocop:disable Metrics/ParameterLists
    def self.search(segment: nil, tags: nil, state: nil, from: nil, to: nil, duration_min: nil,
                    limit: 20, cursor: nil, config: nil)
      Trifle::Traces::Operations::Trace::Search.new(
        segment: segment, tags: tags, state: state,
        from: from, to: to, duration_min: duration_min,
        limit: limit, cursor: cursor, config: config
      ).perform
    end
    # rubocop:enable Metrics/ParameterLists

    def self.payload(record, config: nil)
      Trifle::Traces::Operations::Trace::Payload.new(
        record: record, config: config
      ).perform
    end

    def self.read_artifact(record, name, config: nil)
      (config || default).data_driver.read_artifact(record, name: name)
    end
  end
end
