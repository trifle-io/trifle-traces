# frozen_string_literal: true

module Trifle
  module Traces
    module Tracer
      class Hash # rubocop:disable Metrics/ClassLength
        attr_accessor :key, :meta, :data, :tags, :artifacts, :state, :ignore, :reference, :level

        def initialize(key:, reference: nil, meta: nil, config: nil)
          @key = key
          @meta = meta
          @config = config
          set_defaults!

          trace("Tracer has been initialized for #{key}")
          @reference = reference || liftoff.first
        end

        def set_defaults!
          @tags = []
          @data = []
          @artifacts = []
          @state = :running
          @ignore = false
          @result_prefix = "\u21B3 "
          @block_begin_suffix = " \u21B4"
          @block_end_suffix = " \u21B5"
          @level = 0
        end

        def pop_all_data
          @data.pop(@data.count)
        end

        def pop_all_artifacts
          @artifacts.pop(@artifacts.count)
        end

        def config
          @config || Trifle::Traces.default
        end

        def result_serializer
          @result_serializer ||= config.serializer_class.new
        end

        def keys
          parts = key.split('/')
          parts.count.times.map { |i| parts[0..i].join('/') }
        end

        def trace(message, state: :success, head: false) # rubocop:disable Metrics/MethodLength
          dump_message("#{message}#{@block_begin_suffix if block_given?}", type: head ? :head : :text, state: state)
          if block_given?
            increase
            result = yield
          end
        rescue StandardError => e
          raise e
        ensure
          if block_given?
            decrease
            dump_message("#{message}#{@block_end_suffix}", type: :text, state: e ? :error : state)
            dump_result(result)
          end
          bump
          result
        end

        def dump_message(message, type:, state:)
          @data << { at: now, message: message, state: state, type: type, level: level }
        end

        def dump_result(result)
          @data << {
            at: now, message: "#{@result_prefix}#{sanitize_result(result)}",
            state: :success, type: :raw, level: level
          }
        end

        def sanitize_result(result)
          result_serializer.sanitize(result)
        rescue StandardError
          Trifle::Traces::Serializer::Inspect.sanitize(result)
        end

        def increase
          @level += 1
        end

        def decrease
          @level -= 1
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
          @data << { at: now, message: name, state: :success, type: :media, size: File.size(path) }
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
          config.on_liftoff(self)
        end

        def bump
          return unless @bumped_at && @bumped_at <= now - config.bump_every

          @bumped_at = now
          config.on_bump(self)
        end

        def wrapup
          success! if running?
          config.on_wrapup(self)
        end
      end
    end
  end
end
