# frozen_string_literal: true
require 'json'

module Trifle
  module Traces
    module Serializer
      class Json
        def sanitize(payload)
          payload.to_json
        end
      end
    end
  end
end
