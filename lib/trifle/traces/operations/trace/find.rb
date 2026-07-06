# frozen_string_literal: true

module Trifle
  module Traces
    module Operations
      module Trace
        class Find
          attr_reader :reference

          def initialize(reference:, config: nil)
            @reference = reference
            @config = config
          end

          def config
            @config || Trifle::Traces.default
          end

          def perform
            config.index_driver.find(reference)
          end
        end
      end
    end
  end
end
