# frozen_string_literal: true

module Trifle
  module Traces
    module Middleware
      module RailsController
        def self.included(base)
          base.extend ClassMethods
          base.include InstanceMethods
        end

        module ClassMethods
          def with_trifle_traces(options = {})
            around_action :with_trifle_traces, options
          end
        end

        module InstanceMethods
          def with_trifle_traces
            Trifle::Traces.tracer = Trifle::Traces.default.tracer_class.new(
              key: trace_key, meta: trace_meta, mode: trace_mode
            )
            yield
          rescue => e # rubocop:disable Style/RescueStandardError
            Trifle::Traces.tracer.trace("Exception: #{e}", state: :error)
            Trifle::Traces.tracer.fail!
            raise e
          ensure
            Trifle::Traces.tracer.wrapup
          end

          def trace_key
            "#{params[:controller]}/#{params[:action]}"
          end

          def trace_meta
            [params[:id]].compact
          end

          def trace_mode
            nil # defaults to config.default_mode; override per controller
          end
        end
      end
    end
  end
end
