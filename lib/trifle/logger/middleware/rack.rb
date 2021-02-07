# frozen_string_literal: true

module Trifle
  module Logger
    module Middleware
      class Rack
        def initialize(app)
          @app = app
        end

        def call(env)
          Trifle::Logger.tracer = Trifle::Logger::Tracer::Hash.new
          @status, @headers, @response = @app.call(env)
        rescue => e # rubocop:disable Style/RescueStandardError
          Trifle::Logger.tracer.log("Exception: #{e}", state: :error)
          Trifle::Logger.tracer.fail!
          raise e
        ensure
          Trifle::Logger.tracer.wrapup
          [@status, @headers, @response]
        end
      end
    end
  end
end
