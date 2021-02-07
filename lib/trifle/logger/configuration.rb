# frozen_string_literal: true

module Trifle
  module Logger
    class Configuration
      attr_accessor :tracer_klass, :callbacks

      def initialize
        @callbacks = {
          wrapup: []
        }
      end

      def on_wrapup(tracer)
        @callbacks.fetch(:wrapup, []).each do |c|
          c.call(tracer)
        end
      end

      def on(event, &block)
        @callbacks[event] << block
      end
    end
  end
end
