# frozen_string_literal: true

require 'json'

module Trifle
  module Traces
    module Driver
      module Index
        # MongoDB index driver. Stores one document per trace with the
        # production-proven index set: segments/state, tags/state and a
        # native TTL on expires_at. Client is injected (mongo gem is not
        # a dependency of trifle-traces).
        class Mongo # rubocop:disable Metrics/ClassLength
          attr_accessor :client, :collection_name

          def initialize(client, collection_name: 'trifle_traces')
            @client = client
            @collection_name = collection_name
          end

          def self.setup!(client, collection_name: 'trifle_traces')
            collection = client[collection_name]
            collection.indexes.create_many(
              [
                { key: { segments: 1, state: 1, _id: -1 } },
                { key: { tags: 1, state: 1, _id: -1 } },
                { key: { expires_at: 1 }, expire_after: 0 }
              ]
            )
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

          def search(segment: nil, tags: nil, state: nil, limit: 20, cursor: nil)
            documents = collection.find(
              search_filter(segment: segment, tags: tags, state: state, cursor: cursor)
            ).sort(_id: -1).limit(limit).to_a
            traces = documents.map { |document| record_for(document) }

            { traces: traces, cursor: traces.count == limit ? traces.last&.reference : nil }
          end

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
              state: record.state.to_s,
              tags: record.tags,
              context: record.context,
              length: record.length,
              parts: record.parts,
              last_at: record.last_at,
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
              length: document['length'],
              parts: document['parts'],
              first_at: document['first_at'],
              last_at: document['last_at'],
              retention: document['retention'],
              expires_at: document['expires_at'],
              bucket_id: document['bucket_id']
            )
          end

          def search_filter(segment:, tags:, state:, cursor:)
            filter = {}
            filter[:segments] = { '$in' => Array(segment) } if segment
            filter[:tags] = { '$in' => Array(tags) } if tags
            filter[:state] = state.to_s if state
            filter[:_id] = { '$lt' => bson_id(cursor) } if cursor
            filter
          end
        end
      end
    end
  end
end
