# frozen_string_literal: true

require 'base64'
require 'json'

module Trifle
  module Traces
    module Driver
      module Index
        # Shared normalization and cursor encoding for index-driver searches.
        # Keeping this here makes tag and pagination semantics identical across
        # storage backends while leaving the cursor opaque to callers.
        module Query
          TAG_GROUPS = %i[any all].freeze

          def self.normalize_tags(tags)
            return empty_tags if tags.nil?

            validate_tags_hash!(tags)
            TAG_GROUPS.to_h { |group| [group, normalize_tag_group(tags, group)] }
          end

          def self.encode_cursor(record)
            payload = [record.first_at.to_i, record.first_at.nsec, record.reference.to_s]
            Base64.urlsafe_encode64(JSON.generate(payload), padding: false)
          end

          def self.decode_cursor(cursor)
            return if cursor.nil?

            seconds, nanoseconds, reference = cursor_payload(cursor)
            {
              first_at: Time.at(seconds + Rational(nanoseconds, 1_000_000_000)),
              reference: reference
            }
          rescue ArgumentError, JSON::ParserError, RangeError, TypeError
            raise ArgumentError, 'invalid trace search cursor'
          end

          def self.cursor_payload(cursor)
            payload = JSON.parse(Base64.urlsafe_decode64(cursor))
            valid = payload.is_a?(Array) && payload.count == 3 &&
                    payload[0].is_a?(Integer) && payload[1].is_a?(Integer) && payload[2].is_a?(String)
            raise ArgumentError unless valid

            payload
          end
          private_class_method :cursor_payload

          def self.validate_tags_hash!(tags)
            raise ArgumentError, 'tags must be a hash with :any and/or :all arrays' unless tags.is_a?(Hash)

            unknown = tags.keys.map(&:to_s) - TAG_GROUPS.map(&:to_s)
            raise ArgumentError, "unknown tags groups: #{unknown.join(', ')}" unless unknown.empty?
          end
          private_class_method :validate_tags_hash!

          def self.normalize_tag_group(tags, group)
            value = tags.key?(group) ? tags[group] : tags[group.to_s]
            raise ArgumentError, "tags[:#{group}] must be an array" unless value.nil? || value.is_a?(Array)

            Array(value).compact.uniq
          end
          private_class_method :normalize_tag_group

          def self.empty_tags
            { any: [], all: [] }
          end
          private_class_method :empty_tags
        end
      end
    end
  end
end
