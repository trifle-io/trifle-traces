# frozen_string_literal: true

module Trifle
  module Logger
    module Middleware
      module RailsController
        def self.included(base)
          base.extend ClassMethods
          base.include InstanceMethods
        end

        module ClassMethods
          def with_trifle_logger(options = {})
            around_action :with_trifle_logger, options
          end
        end

        module InstanceMethods
          def with_trifle_logger
            Trifle::Logger.tracer = Trifle::Logger::Tracer::Hash.new(
              key: trace_key, meta: trace_meta
            )
            yield
          rescue => e # rubocop:disable Style/RescueStandardError
            Trifle::Logger.tracer.trace("Exception: #{e}", state: :error)
            Trifle::Logger.tracer.fail!
            raise e
          ensure
            Trifle::Logger.tracer.wrapup
          end

          def trace_key
            "#{params[:controller]}/#{params[:action]}"
          end

          def trace_meta
            [params[:id]].compact
          end
        end
      end
    end
  end
end
