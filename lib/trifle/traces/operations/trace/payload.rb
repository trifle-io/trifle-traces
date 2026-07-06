# frozen_string_literal: true

module Trifle
  module Traces
    module Operations
      module Trace
        class Payload
          attr_reader :record

          def initialize(record:, config: nil)
            @record = record
            @config = config
          end

          def config
            @config || Trifle::Traces.default
          end

          def perform
            config.data_driver.read(record)
          end
        end
      end
    end
  end
end
