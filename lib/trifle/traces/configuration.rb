# frozen_string_literal: true

module Trifle
  module Traces
    class Configuration
      # context and retention accept a static value or anything
      # responding to #call(tracer).
      attr_accessor :tracer_class, :callbacks, :bump_every, :serializer_class,
                    :default_mode, :payload_size_limit, :error_handler,
                    :context, :retention
      attr_writer :index_driver, :data_driver

      DEFAULT_ERROR_HANDLER = lambda do |error, _tracer, phase|
        raise error unless phase == :bump

        warn "Trifle::Traces bump persistence failed (will retry on next flush): #{error.class}: #{error.message}"
      end

      def initialize
        @tracer_class = Trifle::Traces::Tracer::Hash
        @serializer_class = Trifle::Traces::Serializer::Inspect
        @callbacks = { liftoff: [], bump: [], wrapup: [] }
        @bump_every = 15 # seconds
        @default_mode = :live
        @payload_size_limit = 100 * 1024 # bytes; larger messages offload to artifacts
        @error_handler = DEFAULT_ERROR_HANDLER
        @context = {}
        @retention = 7 # days
      end

      def index_driver
        @index_driver || (@null_index_driver ||= Trifle::Traces::Driver::Index::Null.new)
      end

      def data_driver
        @data_driver || (@null_data_driver ||= Trifle::Traces::Driver::Data::Null.new)
      end

      # True once either driver is explicitly configured. Without
      # persistence the dispatcher only generates references and leaves
      # tracer data untouched for user callbacks.
      def persistence?
        !(@index_driver.nil? && @data_driver.nil?)
      end

      def context_for(tracer)
        resolve(@context, tracer) || {}
      end

      def retention_for(tracer)
        Integer(resolve(@retention, tracer))
      end

      def dispatcher_for(tracer)
        Trifle::Traces::Dispatcher.new(tracer: tracer, config: self)
      end

      def on_liftoff(tracer)
        @callbacks.fetch(:liftoff, []).map do |c|
          c.call(tracer)
        end
      end

      def on_bump(tracer)
        @callbacks.fetch(:bump, []).map do |c|
          c.call(tracer)
        end
      end

      def on_wrapup(tracer)
        @callbacks.fetch(:wrapup, []).map do |c|
          c.call(tracer)
        end
      end

      def on(event, &block)
        @callbacks[event] << block
      end

      private

      def resolve(value, tracer)
        value.respond_to?(:call) ? value.call(tracer) : value
      end
    end
  end
end
