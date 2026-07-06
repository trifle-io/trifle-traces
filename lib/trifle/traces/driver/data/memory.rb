# frozen_string_literal: true

module Trifle
  module Traces
    module Driver
      module Data
        # In-process payload storage for tests and development.
        class Memory
          attr_reader :parts, :artifacts

          def initialize
            @parts = ::Hash.new { |hash, key| hash[key] = {} }
            @artifacts = ::Hash.new { |hash, key| hash[key] = {} }
          end

          def description
            self.class.name
          end

          def generate_bucket_id
            0
          end

          def write_part(record, part:, entries:)
            @parts[record.reference][part] = entries.map(&:dup)
          end

          def write_artifact(record, name:, payload: nil, path: nil)
            @artifacts[record.reference][name] = payload || ::File.binread(path)
            name
          end

          def read_part(record, part:)
            @parts[record.reference].fetch(part).map(&:dup)
          end

          def read(record)
            (1..record.parts.to_i).flat_map { |part| read_part(record, part: part) }
          end

          def read_artifact(record, name:)
            @artifacts[record.reference].fetch(name)
          end

          def delete(record)
            @parts.delete(record.reference)
            @artifacts.delete(record.reference)
          end
        end
      end
    end
  end
end
