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
              key: trace_key, meta: trace_meta
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
        end
      end
    end
  end
end
