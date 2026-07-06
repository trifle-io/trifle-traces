# frozen_string_literal: true

module Trifle
  module Traces
    module Driver
      module Index
        # No-op index driver. Generates valid references but persists
        # nothing. The default when no index driver is configured.
        class Null
          def description
            self.class.name
          end

          def generate_reference
            Trifle::Traces::Ref.generate
          end

          def capabilities
            { update: true, delete: true, search: false, ttl: :none }
          end

          def create(record)
            record.reference
          end

          def update(record)
            record.reference
          end

          def delete(_reference)
            nil
          end

          def find(_reference)
            nil
          end

          def search(**_query)
            { traces: [], cursor: nil }
          end
        end
      end
    end
  end
end
