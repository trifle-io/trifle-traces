# frozen_string_literal: true

module Trifle
  module Logger
    module Tracer
      class Null
        def log(_message, **_keywords)
          yield if block_given?
        end

        def tag(_resource); end

        def fail!; end

        def wrapup; end
      end
    end
  end
end
