# frozen_string_literal: true

module Trifle
  module Traces
    module Middleware
      class Rack
        def initialize(app)
          @app = app
        end

        def call(env)
          # TODO: set up key
          # Trifle::Traces.tracer = Trifle::Traces.default.tracer_class.new
          @status, @headers, @response = @app.call(env)
        rescue => e # rubocop:disable Style/RescueStandardError
          Trifle::Traces.tracer&.trace("Exception: #{e}", state: :error)
          Trifle::Traces.tracer&.fail!
          raise e
        ensure
          Trifle::Traces.tracer&.wrapup
          [@status, @headers, @response]
        end
      end
    end
  end
end
