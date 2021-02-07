# frozen_string_literal: true

module Trifle
  module Logger
    module Middleware
      class Sidekiq
        def call(_worker, job, _queue)
          Trifle::Logger.tracer = tracer_for(job: job)
          yield
        rescue => e # rubocop:disable Style/RescueStandardError
          Trifle::Logger.tracer&.trace("Exception: #{e}", state: :error)
          Trifle::Logger.tracer&.fail!
          raise e
        ensure
          Trifle::Logger.tracer&.wrapup
        end

        def tracer_for(job:)
          return nil unless job['logger_key']

          Trifle::Logger.default.tracer_klass.new(
            key: job['logger_key'], meta: job['args']
          )
        end
      end
    end
  end
end
