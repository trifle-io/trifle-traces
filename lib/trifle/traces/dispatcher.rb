# frozen_string_literal: true

module Trifle
  module Traces
    # Orchestrates persistence for a single tracer through the configured
    # index and data drivers. Created at liftoff, invoked from the tracer
    # lifecycle before user callbacks.
    #
    # Modes:
    #   :live     - index entry created at liftoff, updated on bump/wrapup,
    #               data flushed as numbered parts along the way.
    #   :deferred - zero I/O until wrapup, then one part + one index insert.
    class Dispatcher # rubocop:disable Metrics/ClassLength
      attr_reader :tracer, :config, :record

      def initialize(tracer:, config:)
        @tracer = tracer
        @config = config
        @started_at = monotonic_now
        @pending = []
        @pending_artifacts = []
        @failed_phase = nil
        validate_capabilities!
        @record = build_record
      end

      def reference
        record.reference
      end

      def liftoff
        return unless persistence? && live?

        drain
        write_part
        index_driver.create(record)
      rescue StandardError => e
        handle_error(e, :liftoff)
      end

      def bump
        return unless persistence? && live?

        drain
        return if @pending.empty? && @pending_artifacts.empty?

        write_part
        index_driver.update(record)
      rescue StandardError => e
        handle_error(e, :bump)
      end

      def wrapup # rubocop:disable Metrics/AbcSize
        return unless persistence?
        return ignore_wrapup if tracer.ignore

        finalize_record
        drain
        write_part unless @pending.empty? && @pending_artifacts.empty?
        live? ? index_driver.update(record) : index_driver.create(record)
      rescue StandardError => e
        handle_error(e, :wrapup)
      end

      private

      def index_driver
        config.index_driver
      end

      def data_driver
        config.data_driver
      end

      def live?
        tracer.mode == :live
      end

      def persistence?
        config.persistence?
      end

      def validate_capabilities!
        return unless persistence? && tracer.mode == :live
        return if index_driver.capabilities[:update]

        raise Trifle::Traces::Error,
              "#{index_driver.class} does not support update; " \
              'use mode: :deferred for tracers persisted through it'
      end

      def build_record # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
        now = Time.now
        retention = config.retention_for(tracer)
        TraceRecord.new(
          reference: tracer.reference || index_driver.generate_reference,
          key: tracer.key, state: tracer.state,
          tags: tracer.tags.dup, meta: tracer.meta,
          context: config.context_for(tracer),
          duration: 0, counters: TraceRecord.empty_counters,
          length: 0, parts: 0, first_at: now, last_at: now,
          retention: retention, expires_at: now + (retention * 86_400),
          bucket_id: data_driver.generate_bucket_id
        )
      end

      # Moves accumulated tracer data into the dispatcher-held buffer.
      # Entries survive write failures: they stay in @pending until a
      # write_part call succeeds, so a transient storage error degrades
      # into fewer/larger parts instead of losing data.
      def drain
        @pending.concat(tracer.pop_all_data)
        @pending_artifacts.concat(tracer.pop_all_artifacts)
      end

      def write_part
        part = record.parts + 1
        offload_pending!
        upload_artifacts
        data_driver.write_part(record, part: part, entries: @pending)
        record.length += @pending.count
        accumulate_counters(@pending)
        record.parts = part
        sync_record
        @pending = []
      end

      def upload_artifacts
        until @pending_artifacts.empty?
          path = @pending_artifacts.first
          data_driver.write_artifact(record, name: File.basename(path), path: path)
          @pending_artifacts.shift
        end
      end

      # Entries with oversized messages are stored as artifacts and
      # replaced inline with a media entry, keeping index parts small.
      # Already-offloaded entries keep their replacement if a later
      # offload raises; the failing entry retries on the next flush.
      def offload_pending!
        @pending.map! do |entry|
          message = entry[:message].to_s
          next entry if message.bytesize <= config.payload_size_limit

          name = "part_row_#{Ref.generate.downcase}.txt"
          data_driver.write_artifact(record, name: name, payload: message)
          entry.merge(message: name, type: :media, size: message.bytesize)
        end
      end

      def sync_record
        record.state = tracer.state
        record.tags = tracer.tags.uniq.compact.sort
        record.last_at = Time.now
        update_duration
      end

      def accumulate_counters(entries)
        counters = duplicate_counters
        entries.each { |entry| accumulate_entry(counters, entry) }
        record.counters = counters
      end

      def duplicate_counters
        {
          states: record.counters[:states].dup,
          types: record.counters[:types].dup,
          max_level: record.counters[:max_level]
        }
      end

      def accumulate_entry(counters, entry)
        increment_counter(counters[:states], entry[:state])
        increment_counter(counters[:types], entry[:type])
        counters[:max_level] = [counters[:max_level], entry.fetch(:level, 0).to_i].max
      end

      def increment_counter(counters, key)
        key = key&.to_sym
        counters[key] += 1 if counters.key?(key)
      end

      def update_duration
        elapsed_ms = ((monotonic_now - @started_at) * 1000).round
        record.duration = [record.duration, elapsed_ms].max
      end

      def monotonic_now
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      def finalize_record
        sync_record
      end

      def ignore_wrapup
        return unless live?

        index_driver.delete(record.reference) if index_driver.capabilities[:delete]
        begin
          data_driver.delete(record)
        rescue StandardError
          nil # best-effort purge; the index entry is already gone
        end
      end

      def handle_error(error, phase)
        config.error_handler.call(error, tracer, phase)
      end
    end
  end
end
