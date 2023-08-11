# frozen_string_literal: true

module Trifle
  module Traces
    module Serializer
      class String
        def sanitize(payload)
          payload.to_s
        end
      end
    end
  end
end
