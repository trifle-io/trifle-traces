# frozen_string_literal: true

module Trifle
  module Logger
    module Middleware
      class Rack
        def initialize(app)
          @app = app
        end

        def call(env)
          # TODO: set up key
          # Trifle::Logger.tracer = Trifle::Logger.default.tracer_class.new
          @status, @headers, @response = @app.call(env)
        rescue => e # rubocop:disable Style/RescueStandardError
          Trifle::Logger.tracer&.trace("Exception: #{e}", state: :error)
          Trifle::Logger.tracer&.fail!
          raise e
        ensure
          Trifle::Logger.tracer&.wrapup
          [@status, @headers, @response]
        end
      end
    end
  end
end
