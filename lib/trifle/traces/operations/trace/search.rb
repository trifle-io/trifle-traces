# frozen_string_literal: true

module Trifle
  module Traces
    module Operations
      module Trace
        class Search
          # rubocop:disable Metrics/ParameterLists
          def initialize(segment: nil, tags: nil, state: nil, from: nil, to: nil, duration_min: nil,
                         limit: 20, cursor: nil, config: nil)
            @segment = segment
            @tags = Trifle::Traces::Driver::Index::Query.normalize_tags(tags)
            @state = state
            @from = from
            @to = to
            @duration_min = duration_min
            @limit = limit
            @cursor = cursor
            @config = config
          end
          # rubocop:enable Metrics/ParameterLists

          def config
            @config || Trifle::Traces.default
          end

          def perform
            config.index_driver.search(
              segment: @segment, tags: @tags, state: @state,
              from: @from, to: @to, duration_min: @duration_min,
              limit: @limit, cursor: @cursor
            )
          end
        end
      end
    end
  end
end
