# frozen_string_literal: true

module Trifle
  module Traces
    module Tracer
      class Hash # rubocop:disable Metrics/ClassLength
        attr_accessor :key, :meta, :data, :tags, :artifacts, :state, :ignore, :reference

        def initialize(key:, reference: nil, meta: nil, config: nil)
          @key = key
          @meta = meta
          @config = config
          @result_serializer = config.serializer_class.new
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
          @result_prefix = '=> '
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

        def keys
          parts = key.split('/')
          parts.count.times.map { |i| parts[0..i].join('/') }
        end

        def trace(message, state: :success, head: false) # rubocop:disable Metrics/MethodLength
          result = yield if block_given?
        rescue StandardError => e
          raise e
        ensure
          dump_message(
            message,
            type: head ? :head : :text,
            state: e ? :error : state
          )
          dump_result(result) if block_given?
          bump
          result
        end

        def dump_message(message, type:, state:)
          @data << { at: now, message: message, state: state, type: type }
        end

        def dump_result(result)
          @data << {
            at: now, message: "#{@result_prefix}#{sanitize_result(result)}",
            state: :success, type: :raw
          }
        end

        def sanitize_result(result)
          @result_serializer.sanitize(result)
        rescue StandardError
          Trifle::Traces::Serializer::Inspect.sanitize(result)
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
