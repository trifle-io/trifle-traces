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
            @records[record.reference] = duplicate_record(record)
            record.reference
          end

          def update(record)
            @records[record.reference] = duplicate_record(record)
            record.reference
          end

          def delete(reference)
            @records.delete(reference)
          end

          def find(reference)
            record = @records[reference]
            record && duplicate_record(record)
          end

          # rubocop:disable Metrics/AbcSize, Metrics/ParameterLists
          def search(segment: nil, tags: nil, state: nil, from: nil, to: nil, duration_min: nil,
                     limit: 20, cursor: nil)
            filters = search_filters(
              segment: segment, tags: tags, state: state,
              from: from, to: to, duration_min: duration_min
            )
            position = Query.decode_cursor(cursor)
            results = @records.values.sort_by { |record| [record.first_at, record.reference] }.reverse
            results = results.select { |record| matches?(record, filters) }
            results = results.select { |r| after_cursor?(r, position) } if position
            page = results.first(limit).map { |record| duplicate_record(record) }

            { traces: page, cursor: page.count == limit ? Query.encode_cursor(page.last) : nil }
          end
          # rubocop:enable Metrics/AbcSize, Metrics/ParameterLists

          private

          def search_filters(filters)
            filters.merge(tags: Query.normalize_tags(filters[:tags]))
          end

          def matches?(record, filters)
            segment_matches?(record, filters[:segment]) &&
              tags_match?(record, filters[:tags]) &&
              state_matches?(record, filters[:state]) &&
              time_matches?(record, filters[:from], filters[:to]) &&
              duration_matches?(record, filters[:duration_min])
          end

          def segment_matches?(record, segment)
            segment.nil? || record.segments.include?(segment)
          end

          def tags_match?(record, tags)
            (tags[:any].empty? || (record.tags & tags[:any]).any?) &&
              (tags[:all].empty? || (tags[:all] - record.tags).empty?)
          end

          def state_matches?(record, state)
            state.nil? || record.state.to_s == state.to_s
          end

          def time_matches?(record, from, to)
            (from.nil? || record.first_at >= from) && (to.nil? || record.first_at < to)
          end

          def duration_matches?(record, minimum)
            minimum.nil? || record.duration >= minimum
          end

          def after_cursor?(record, position)
            record.first_at < position[:first_at] ||
              (record.first_at == position[:first_at] && record.reference < position[:reference])
          end

          def duplicate_record(record)
            copy = record.dup
            copy.tags = record.tags.dup
            copy.context = record.context.dup
            copy.counters = {
              states: record.counters[:states].dup,
              types: record.counters[:types].dup,
              max_level: record.counters[:max_level]
            }
            copy
          end
        end
      end
    end
  end
end
