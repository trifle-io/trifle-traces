# frozen_string_literal: true

module Trifle
  module Logger
    module Middleware
      class Sidekiq
        def call(_worker, job, _queue)
          Trifle::Logger.tracer = Tracer.new(
            namespace: job['namespace'], attrs: job['args']
          )
          yield
        rescue => e # rubocop:disable Style/RescueStandardError
          Trifle::Logger.tracer.log("Exception: #{e}", state: :error)
          Trifle::Logger.tracer.fail!
          raise e
        ensure
          Trifle::Logger.tracer.wrapup
        end
      end
    end
  end
end
