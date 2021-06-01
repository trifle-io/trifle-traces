# frozen_string_literal: true

module Trifle
  module Logger
    module Tracer
      class Hash
        attr_accessor :key, :meta, :data, :tags, :artifacts, :state, :ignore, :reference

        def initialize(key:, meta: nil)
          @key = key
          @meta = meta
          @data = []
          @tags = []
          @artifacts = []
          @state = :running
          @ignore = false
          @result_prefix = '=> '

          trace("Trifle::Trace has been initialized for #{key}")
          @reference = liftoff.first
        end

        def keys
          parts = key.split('/')
          parts.count.times.map { |i| parts[0..i].join('/') }
        end

        def trace(message, state: :success, head: false) # rubocop:disable Metrics/MethodLength
          result = yield if block_given?
        rescue => e # rubocop:disable Style/RescueStandardError
          raise e
        ensure
          dump_message(
            message,
            head: head, state: block_given? && result.nil? || e ? :error : state
          )
          dump_result(result) if block_given?
          bump
          result
        end

        def dump_message(message, head:, state:)
          @data << {
            at: now, message: message,
            state: state, head: head, meta: false, media: false
          }
        end

        def dump_result(result)
          @data << {
            at: now, message: "#{@result_prefix}#{result.inspect}",
            state: :success, head: false, meta: true, media: false
          }
        end

        def now
          Time.now.to_i
        end

        def tag(tag)
          @tags << tag
          bump
          tag
        end

        def artifact(name, path)
          @data << {
            at: now, message: name,
            state: :success, head: false, meta: false, media: true
          }
          @artifacts << path
          bump
          path
        end

        def fail!
          @state = :error
        end

        def warn!
          @state = :warning
        end

        def success!
          @state = :success
        end

        def success?
          @state == :success
        end

        def running?
          @state == :running
        end

        def ignore!
          @ignore = true
        end

        def liftoff
          @bumped_at = now
          Trifle::Logger.default.on_liftoff(self)
        end

        def bump
          return unless @bumped_at && @bumped_at <= now - Trifle::Logger.default.bump_every

          @bumped_at = now
          Trifle::Logger.default.on_bump(self)
        end

        def wrapup
          success! if running?
          Trifle::Logger.default.on_wrapup(self)
        end
      end
    end
  end
end
