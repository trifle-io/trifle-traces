# frozen_string_literal: true

module Trifle
  module Traces
    module Traces
      class Null
        def trace(_message, **_keywords)
          yield if block_given?
        end

        def tag(_tag); end

        def artifact(_name, _path); end

        def fail!; end

        def warn!; end

        def ignore!; end

        def liftoff; end

        def bump; end

        def wrapup; end
      end
    end
  end
end
