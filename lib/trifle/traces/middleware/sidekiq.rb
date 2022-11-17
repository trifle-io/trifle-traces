# frozen_string_literal: true

module Trifle
  module Traces
    module Middleware
      class Sidekiq
        def call(_worker, job, _queue)
          Trifle::Traces.tracer = tracer_for(job: job)
          yield
        rescue => e # rubocop:disable Style/RescueStandardError
          Trifle::Traces.tracer&.trace("Exception: #{e}", state: :error)
          Trifle::Traces.tracer&.fail!
          raise e
        ensure
          Trifle::Traces.tracer&.wrapup
        end

        def tracer_for(job:)
          puts "Trifle::Traces tracer_for #{job['tracer_key']}"
          return nil unless job['tracer_key']

          Trifle::Traces.default.tracer_class.new(
            key: job['tracer_key'], meta: job['args']
          )
        end
      end
    end
  end
end
