# frozen_string_literal: true

module Trifle
  module Traces
    # Optional activity tracking, independent of user lifecycle callbacks.
    module Stats
      def self.track(record, config)
        return unless config

        Trifle::Stats.track(
          key: record.key, at: config.tz.utc_to_local(record.last_at.getutc), config: config,
          values: values(record)
        )
      rescue StandardError => e
        warn "Trifle::Traces trace=#{record.reference} stats tracking failed: #{e.class}: #{e.message}"
      end

      def self.values(record)
        state = record.state.to_s
        sample = { count: 1, sum: record.duration, square: record.duration**2 }
        {
          count: 1, states: { state => 1 }, entries: { count: record.length },
          duration: sample.merge(states: { state => sample })
        }
      end
    end
  end
end
