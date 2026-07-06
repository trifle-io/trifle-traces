# frozen_string_literal: true

module Trifle
  module Traces
    module Driver
      module Data
        # No-op payload storage. The default when no data driver is
        # configured - index-only setups are valid.
        # rubocop:disable Lint/UnusedMethodArgument
        class Null
          def description
            self.class.name
          end

          def generate_bucket_id
            0
          end

          def write_part(_record, part:, entries:); end

          def write_artifact(_record, name:, payload: nil, path: nil)
            name
          end

          def read_part(_record, part:)
            []
          end

          def read(_record)
            []
          end

          def read_artifact(_record, name:)
            nil
          end

          def delete(_record)
            nil
          end
        end
        # rubocop:enable Lint/UnusedMethodArgument
      end
    end
  end
end
