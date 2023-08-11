# frozen_string_literal: true

module Trifle
  module Traces
    module Serializer
      class Inspect
        def sanitize(payload)
          payload.inspect
        end
      end
    end
  end
end
