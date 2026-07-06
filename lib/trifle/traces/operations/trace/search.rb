# frozen_string_literal: true

module Trifle
  module Traces
    module Operations
      module Trace
        class Search
          def initialize(segment: nil, tags: nil, state: nil, limit: 20, cursor: nil, config: nil) # rubocop:disable Metrics/ParameterLists
            @segment = segment
            @tags = tags
            @state = state
            @limit = limit
            @cursor = cursor
            @config = config
          end

          def config
            @config || Trifle::Traces.default
          end

          def perform
            config.index_driver.search(
              segment: @segment, tags: @tags, state: @state,
              limit: @limit, cursor: @cursor
            )
          end
        end
      end
    end
  end
end
