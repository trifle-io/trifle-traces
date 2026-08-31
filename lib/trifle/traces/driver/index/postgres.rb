# frozen_string_literal: true

require 'json'
require 'time'

module Trifle
  module Traces
    module Driver
      module Index
        # PostgreSQL metadata index compatible with Trifle.Traces for Elixir.
        # The injected client must implement PG::Connection's exec/exec_params
        # interface; pg remains an optional host-application dependency.
        class Postgres # rubocop:disable Metrics/ClassLength
          attr_reader :client, :table_name

          def initialize(client, table_name: 'trifle_traces')
            @client = client
            @table_name = self.class.validate_table_name!(table_name)
          end

          def self.setup!(client, table_name: 'trifle_traces') # rubocop:disable Metrics/MethodLength
            table_name = validate_table_name!(table_name)

            statements = [
              <<~SQL,
                CREATE TABLE IF NOT EXISTS #{table_name} (
                  reference TEXT PRIMARY KEY,
                  key TEXT NOT NULL,
                  segments JSONB NOT NULL DEFAULT '[]'::jsonb,
                  state VARCHAR(32) NOT NULL,
                  tags JSONB NOT NULL DEFAULT '[]'::jsonb,
                  meta JSONB,
                  context JSONB NOT NULL DEFAULT '{}'::jsonb,
                  duration BIGINT NOT NULL DEFAULT 0,
                  counters JSONB NOT NULL DEFAULT '{}'::jsonb,
                  length BIGINT NOT NULL DEFAULT 0,
                  parts INTEGER NOT NULL DEFAULT 0,
                  first_at TIMESTAMPTZ NOT NULL,
                  last_at TIMESTAMPTZ NOT NULL,
                  retention INTEGER NOT NULL,
                  expires_at TIMESTAMPTZ NOT NULL,
                  bucket_id INTEGER NOT NULL DEFAULT 0
                )
              SQL
              "CREATE INDEX IF NOT EXISTS #{table_name}_segments_gin " \
                "ON #{table_name} USING GIN (segments)",
              "CREATE INDEX IF NOT EXISTS #{table_name}_tags_gin " \
                "ON #{table_name} USING GIN (tags)",
              "CREATE INDEX IF NOT EXISTS #{table_name}_state_started " \
                "ON #{table_name} (state, first_at DESC, reference DESC)",
              "CREATE INDEX IF NOT EXISTS #{table_name}_started " \
                "ON #{table_name} (first_at DESC, reference DESC)",
              "CREATE INDEX IF NOT EXISTS #{table_name}_duration_started " \
                "ON #{table_name} (duration, first_at DESC, reference DESC)",
              "CREATE INDEX IF NOT EXISTS #{table_name}_expires_at " \
                "ON #{table_name} (expires_at)"
            ]

            statements.each { |statement| client.exec(statement) }
            :ok
          end

          def self.cleanup!(client, table_name: 'trifle_traces', before: Time.now)
            table_name = validate_table_name!(table_name)
            result = client.exec_params("DELETE FROM #{table_name} WHERE expires_at <= $1", [timestamp(before)])
            result.cmd_tuples
          end

          def cleanup!(before: Time.now)
            self.class.cleanup!(client, table_name: table_name, before: before)
          end

          def description
            self.class.name
          end

          def generate_reference
            Trifle::Traces::Ref.generate
          end

          def capabilities
            { update: true, delete: true, search: true, ttl: :cleanup }
          end

          def create(record) # rubocop:disable Metrics/MethodLength
            client.exec_params(
              <<~SQL,
                INSERT INTO #{table_name} (
                  reference, key, segments, state, tags, meta, context,
                  duration, counters, length, parts, first_at, last_at,
                  retention, expires_at, bucket_id
                ) VALUES (
                  $1, $2, $3::jsonb, $4, $5::jsonb, $6::jsonb, $7::jsonb,
                  $8, $9::jsonb, $10, $11, $12, $13, $14, $15, $16
                )
              SQL
              create_params(record)
            )

            record.reference
          end

          def update(record) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
            client.exec_params(
              <<~SQL,
                UPDATE #{table_name}
                SET state = $1, tags = $2::jsonb, context = $3::jsonb,
                    duration = $4, counters = $5::jsonb, length = $6,
                    parts = $7, last_at = $8, expires_at = $9
                WHERE reference = $10
              SQL
              [
                record.state.to_s, JSON.generate(record.tags), JSON.generate(record.context || {}),
                record.duration, JSON.generate(record.counters), record.length, record.parts,
                self.class.timestamp(record.last_at), self.class.timestamp(record.expires_at),
                record.reference.to_s
              ]
            )

            record.reference
          end

          def delete(reference)
            client.exec_params("DELETE FROM #{table_name} WHERE reference = $1", [reference.to_s])
            nil
          end

          def find(reference)
            row = client.exec_params("SELECT * FROM #{table_name} WHERE reference = $1", [reference.to_s]).first
            row && record_for(row)
          end

          # rubocop:disable Metrics/ParameterLists
          def search(segment: nil, tags: nil, state: nil, from: nil, to: nil, duration_min: nil,
                     limit: 20, cursor: nil)
            limit = normalize_limit(limit)
            query, params = search_query(
              segment: segment, tags: tags, state: state, from: from, to: to,
              duration_min: duration_min, limit: limit, cursor: cursor
            )
            traces = client.exec_params(query, params).map { |row| record_for(row) }

            { traces: traces, cursor: traces.count == limit ? Query.encode_cursor(traces.last) : nil }
          end
          # rubocop:enable Metrics/ParameterLists

          def self.validate_table_name!(table_name)
            value = table_name.to_s
            return value if value.match?(/\A[a-zA-Z_][a-zA-Z0-9_]*\z/)

            raise ArgumentError, "invalid PostgreSQL table name: #{table_name.inspect}"
          end

          def self.timestamp(value)
            value.utc.iso8601(6)
          end

          private

          def create_params(record) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
            [
              record.reference.to_s,
              record.key.to_s,
              JSON.generate(record.segments),
              record.state.to_s,
              JSON.generate(record.tags || []),
              record.meta.nil? ? nil : JSON.generate(record.meta),
              JSON.generate(record.context || {}),
              record.duration,
              JSON.generate(record.counters),
              record.length,
              record.parts,
              self.class.timestamp(record.first_at),
              self.class.timestamp(record.last_at),
              record.retention,
              self.class.timestamp(record.expires_at),
              record.bucket_id
            ]
          end

          # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength
          # rubocop:disable Metrics/ParameterLists, Metrics/PerceivedComplexity
          def search_query(segment:, tags:, state:, from:, to:, duration_min:, limit:, cursor:)
            clauses = []
            params = []
            normalized_tags = Query.normalize_tags(tags)

            add_json_contains(clauses, params, 'segments', [segment]) if segment
            add_any_tags(clauses, params, normalized_tags[:any])
            add_json_contains(clauses, params, 'tags', normalized_tags[:all]) unless normalized_tags[:all].empty?
            add_condition(clauses, params, 'state =', state.to_s) if state
            add_condition(clauses, params, 'first_at >=', self.class.timestamp(from)) if from
            add_condition(clauses, params, 'first_at <', self.class.timestamp(to)) if to
            add_condition(clauses, params, 'duration >=', duration_min) unless duration_min.nil?
            add_cursor(clauses, params, Query.decode_cursor(cursor)) if cursor

            params << limit
            where = clauses.empty? ? '' : " WHERE #{clauses.join(' AND ')}"
            [
              "SELECT * FROM #{table_name}#{where} " \
                "ORDER BY first_at DESC, reference DESC LIMIT $#{params.count}",
              params
            ]
          end
          # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength
          # rubocop:enable Metrics/ParameterLists, Metrics/PerceivedComplexity

          def add_json_contains(clauses, params, column, values)
            params << JSON.generate(values)
            clauses << "#{column} @> $#{params.count}::jsonb"
          end

          def add_any_tags(clauses, params, tags)
            return if tags.empty?

            conditions = tags.map do |tag|
              params << JSON.generate([tag])
              "tags @> $#{params.count}::jsonb"
            end
            clauses << "(#{conditions.join(' OR ')})"
          end

          def add_condition(clauses, params, expression, value)
            params << value
            clauses << "#{expression} $#{params.count}"
          end

          def add_cursor(clauses, params, position)
            params << self.class.timestamp(position[:first_at])
            at_param = params.count
            params << position[:reference]
            reference_param = params.count
            clauses << "(first_at < $#{at_param} OR " \
                       "(first_at = $#{at_param} AND reference < $#{reference_param}))"
          end

          def record_for(row) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
            Trifle::Traces::TraceRecord.new(
              reference: row['reference'],
              key: row['key'],
              state: row['state']&.to_sym,
              tags: parse_json(row['tags']) || [],
              meta: parse_json(row['meta']),
              context: parse_json(row['context']) || {},
              duration: row['duration'].to_i,
              counters: counters_for(parse_json(row['counters'])),
              length: row['length'].to_i,
              parts: row['parts'].to_i,
              first_at: parse_time(row['first_at']),
              last_at: parse_time(row['last_at']),
              retention: row['retention'].to_i,
              expires_at: parse_time(row['expires_at']),
              bucket_id: row['bucket_id'].to_i
            )
          end

          def counters_for(counters)
            counters ||= {}
            {
              states: (counters['states'] || {}).transform_keys(&:to_sym),
              types: (counters['types'] || {}).transform_keys(&:to_sym),
              max_level: counters['max_level'].to_i
            }
          end

          def parse_json(value)
            value.is_a?(String) ? JSON.parse(value) : value
          end

          def parse_time(value)
            value.is_a?(Time) ? value : Time.parse(value.to_s)
          end

          def normalize_limit(limit)
            value = Integer(limit)
            return value if value.positive?

            raise ArgumentError, 'trace search limit must be a positive integer'
          rescue ArgumentError, TypeError
            raise ArgumentError, 'trace search limit must be a positive integer'
          end
        end
      end
    end
  end
end
