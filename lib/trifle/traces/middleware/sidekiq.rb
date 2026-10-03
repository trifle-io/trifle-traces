# frozen_string_literal: true

module Trifle
  module Traces
    module Middleware
      class Sidekiq
        include ::Sidekiq::ServerMiddleware if const_defined?('::Sidekiq::ServerMiddleware')

        def call(worker, job, _queue)
          Trifle::Traces.tracer = tracer_for(job: job, worker: worker)
          yield
        rescue => e # rubocop:disable Style/RescueStandardError
          Trifle::Traces.tracer&.trace("Exception: #{e}", state: :error)
          Trifle::Traces.tracer&.fail!
          raise e
        ensure
          Trifle::Traces.tracer&.wrapup
        end

        def tracer_for(job:, worker: nil)
          return nil unless job['tracer_key']

          Trifle::Traces.default.tracer_class.new(
            key: job['tracer_key'], meta: job['args'], mode: job['tracer_mode'] || worker_default_mode(worker)
          )
        end

        private

        def worker_default_mode(worker)
          return unless worker.class.respond_to?(:get_sidekiq_options)

          worker.class.get_sidekiq_options['tracer_mode']
        end
      end
    end
  end
end
