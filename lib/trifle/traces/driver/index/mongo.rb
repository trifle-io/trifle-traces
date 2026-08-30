# frozen_string_literal: true

require 'json'

module Trifle
  module Traces
    module Driver
      module Index
        # MongoDB index driver. Stores one document per trace with the
        # compound search indexes and a native TTL on expires_at. Client
        # is injected (mongo gem is not
        # a dependency of trifle-traces).
        class Mongo # rubocop:disable Metrics/ClassLength
          INDEXES = [
            { key: { segments: 1, first_at: -1, _id: -1 } },
            { key: { tags: 1, first_at: -1, _id: -1 } },
            { key: { state: 1, first_at: -1, _id: -1 } },
            { key: { first_at: -1, _id: -1 } },
            { key: { duration: 1, first_at: -1, _id: -1 } },
            { key: { expires_at: 1 }, expire_after: 0 }
          ].freeze

          attr_accessor :client, :collection_name

          def initialize(client, collection_name: 'trifle_traces')
            @client = client
            @collection_name = collection_name
          end

          def self.setup!(client, collection_name: 'trifle_traces')
            client[collection_name].indexes.create_many(INDEXES)
          end

          def description
            self.class.name
          end

          def generate_reference
            BSON::ObjectId.new.to_s
          end

          def capabilities
            { update: true, delete: true, search: true, ttl: :native }
          end

          def create(record)
            collection.insert_one(document_for(record))
            record.reference
          end

          def update(record)
            collection.update_one(
              { _id: bson_id(record.reference) },
              { '$set' => mutable_fields_for(record) }
            )
            record.reference
          end

          def delete(reference)
            collection.delete_one(_id: bson_id(reference))
          end

          def find(reference)
            document = collection.find(_id: bson_id(reference)).first
            document && record_for(document)
          end

          # rubocop:disable Metrics/ParameterLists
          def search(segment: nil, tags: nil, state: nil, from: nil, to: nil, duration_min: nil,
                     limit: 20, cursor: nil)
            documents = collection.find(
              search_filter(
                segment: segment, tags: tags, state: state, from: from, to: to,
                duration_min: duration_min, cursor: cursor
              )
            ).sort(first_at: -1, _id: -1).limit(limit).to_a
            traces = documents.map { |document| record_for(document) }

            { traces: traces, cursor: traces.count == limit ? Query.encode_cursor(traces.last) : nil }
          end
          # rubocop:enable Metrics/ParameterLists

          private

          def collection
            client[collection_name]
          end

          def bson_id(reference)
            BSON::ObjectId.from_string(reference)
          rescue BSON::Error::InvalidObjectId
            reference
          end

          def document_for(record)
            mutable_fields_for(record).merge(
              _id: bson_id(record.reference),
              key: record.key,
              segments: record.segments,
              meta: record.meta&.to_json,
              first_at: record.first_at,
              retention: record.retention,
              bucket_id: record.bucket_id
            )
          end

          def mutable_fields_for(record)
            {
              state: record.state.to_s, tags: record.tags, context: record.context,
              duration: record.duration, counters: record.counters,
              length: record.length, parts: record.parts, last_at: record.last_at,
              expires_at: record.expires_at
            }
          end

          def record_for(document) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
            Trifle::Traces::TraceRecord.new(
              reference: document['_id'].to_s,
              key: document['key'],
              state: document['state']&.to_sym,
              tags: document['tags'] || [],
              meta: document['meta'] && JSON.parse(document['meta']),
              context: document['context'] || {},
              duration: document['duration'],
              counters: counters_for(document['counters']),
              length: document['length'],
              parts: document['parts'],
              first_at: document['first_at'],
              last_at: document['last_at'],
              retention: document['retention'],
              expires_at: document['expires_at'],
              bucket_id: document['bucket_id']
            )
          end

          def counters_for(counters)
            {
              states: counters.fetch('states').transform_keys(&:to_sym),
              types: counters.fetch('types').transform_keys(&:to_sym),
              max_level: counters.fetch('max_level')
            }
          end

          # rubocop:disable Metrics/ParameterLists
          def search_filter(segment:, tags:, state:, from:, to:, duration_min:, cursor:)
            tags = Query.normalize_tags(tags)
            filter = {}
            filter[:segments] = segment if segment
            filter[:state] = state.to_s if state
            filter[:duration] = { '$gte' => duration_min } if duration_min
            add_tag_filter(filter, tags)
            add_time_filter(filter, from, to)
            add_cursor_filter(filter, Query.decode_cursor(cursor)) if cursor
            filter
          end
          # rubocop:enable Metrics/ParameterLists

          def add_tag_filter(filter, tags)
            conditions = {}
            conditions['$in'] = tags[:any] unless tags[:any].empty?
            conditions['$all'] = tags[:all] unless tags[:all].empty?
            filter[:tags] = conditions unless conditions.empty?
          end

          def add_time_filter(filter, from, to)
            conditions = {}
            conditions['$gte'] = from if from
            conditions['$lt'] = to if to
            filter[:first_at] = conditions unless conditions.empty?
          end

          def add_cursor_filter(filter, position)
            filter['$or'] = [
              { first_at: { '$lt' => position[:first_at] } },
              {
                first_at: position[:first_at],
                _id: { '$lt' => bson_id(position[:reference]) }
              }
            ]
          end
        end
      end
    end
  end
end
