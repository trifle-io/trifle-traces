# frozen_string_literal: true

module Trifle
  module Logger
    module Tracer
      class Hash
        attr_accessor :key, :meta, :data, :tags, :state

        def initialize(key:, meta: nil)
          @key = key
          @meta = meta
          @data = []
          @tags = []
          @state = :success
          @result_prefix = '=> '

          trace("Trifle::Trace has been initialized for #{key}")
        end

        def keys
          parts = key.split('/')
          parts.count.times.map { |i| parts[0..i].join('/') }
        end

        def trace(message, state: :success, head: false)
          result = yield if block_given?
        rescue => e # rubocop:disable Style/RescueStandardError
          raise e
        ensure
          dump_message(
            message,
            head: head, state: block_given? && result.nil? || e ? :error : state
          )
          dump_result(result) if block_given?
          result
        end

        def dump_message(message, head:, state:)
          @data << {
            at: now, message: message,
            state: state, head: head, meta: false
          }
        end

        def dump_result(result)
          @data << {
            at: now, message: "#{@result_prefix}#{result.inspect}",
            state: :success, head: false, meta: true
          }
        end

        def now
          Time.now.to_i
        end

        def tag(tag)
          @tags << tag
        end

        def fail!
          @state = :error
        end

        def success?
          @state == :success
        end

        def wrapup
          Trifle::Logger.default.on_wrapup(self)
        end
      end
    end
  end
end
