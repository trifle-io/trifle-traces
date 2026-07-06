# frozen_string_literal: true

module Trifle
  module Traces
    module Driver
      module Index
        # In-process reference implementation of the index driver
        # contract. Intended for tests and development.
        class Memory
          attr_reader :records

          def initialize
            @records = {}
          end

          def description
            self.class.name
          end

          def generate_reference
            Trifle::Traces::Ref.generate
          end

          def capabilities
            { update: true, delete: true, search: true, ttl: :none }
          end

          def create(record)
            @records[record.reference] = record.dup
            record.reference
          end

          def update(record)
            @records[record.reference] = record.dup
            record.reference
          end

          def delete(reference)
            @records.delete(reference)
          end

          def find(reference)
            record = @records[reference]
            record&.dup
          end

          def search(segment: nil, tags: nil, state: nil, limit: 20, cursor: nil) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
            results = @records.values.sort_by(&:reference).reverse
            results = results.select { |r| r.segments.include?(segment) } if segment
            results = results.select { |r| (r.tags & Array(tags)).any? } if tags
            results = results.select { |r| r.state.to_s == state.to_s } if state
            results = results.select { |r| r.reference < cursor } if cursor
            page = results.first(limit).map(&:dup)

            { traces: page, cursor: page.count == limit ? page.last&.reference : nil }
          end
        end
      end
    end
  end
end
