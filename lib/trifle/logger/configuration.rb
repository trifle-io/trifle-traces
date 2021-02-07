# frozen_string_literal: true

module Trifle
  module Logger
    class Configuration
      attr_accessor :callbacks

      def initialize
        @callbacks = {}
      end

      def itsawrap(tracer)
        puts "Wrapping up #{tracer}"
      end

      def on(event, &block)
        @callbacks[event] << block
      end
    end
  end
end
