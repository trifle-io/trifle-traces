# frozen_string_literal: true

module Trifle
  module Traces
    module Tracer
      class Null
        def initialize(**_kwargs); end

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
