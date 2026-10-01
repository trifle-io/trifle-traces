# frozen_string_literal: true

require_relative 'encoding'

module Trifle
  module Traces
    module Driver
      module Data
        # S3-compatible payload storage (AWS S3, Hetzner, Cloudflare R2,
        # minio, ...). Client is injected (any Aws::S3::Client-compatible
        # object); aws-sdk-s3 is not a dependency of trifle-traces.
        #
        # Objects live under "<retention>/<prefix>/<key>/<reference>/",
        # so a single bucket lifecycle rule per retention class expires
        # payloads. Multiple buckets spread writes across per-bucket rate
        # limits; the bucket name is chosen once per trace (record.bucket_name).
        class S3
          include Encoding

          attr_accessor :client, :buckets, :prefix

          def initialize(client:, buckets:, prefix: 'traces', gzip: false)
            @client = client
            @buckets = Array(buckets)
            @prefix = prefix
            @gzip = gzip
          end

          # Creates one lifecycle expiration rule per retention class on
          # every bucket. Run once during setup, not per deploy.
          def self.setup!(client:, buckets:, retentions:, prefix: 'traces') # rubocop:disable Metrics/MethodLength
            Array(buckets).each do |bucket|
              client.put_bucket_lifecycle_configuration(
                bucket: bucket,
                lifecycle_configuration: {
                  rules: Array(retentions).map do |days|
                    {
                      id: "trifle-traces-#{days}d",
                      status: 'Enabled',
                      filter: { prefix: "#{days}/#{prefix}/" },
                      expiration: { days: days }
                    }
                  end
                }
              )
            end
          end

          def description
            self.class.name
          end

          def generate_bucket_name
            buckets.sample
          end

          def write_part(record, part:, entries:)
            client.put_object(
              bucket: record.bucket_name,
              key: object_key(record, part_name(part)),
              body: pack_entries(entries)
            )
          end

          def write_artifact(record, name:, payload: nil, path: nil)
            body = payload || ::File.open(path, 'rb')
            client.put_object(
              bucket: record.bucket_name,
              key: object_key(record, "artifacts/#{name}"),
              body: body
            )
            name
          ensure
            body.close if body.respond_to?(:close)
          end

          def read_part(record, part:)
            unpack_entries(get(record, part_name(part)))
          end

          def read(record)
            (1..record.parts.to_i).flat_map { |part| read_part(record, part: part) }
          end

          def read_artifact(record, name:)
            get(record, "artifacts/#{name}")
          end

          def delete(record)
            bucket = record.bucket_name
            response = client.list_objects_v2(bucket: bucket, prefix: object_key(record, ''))
            keys = response.contents.map { |object| { key: object.key } }
            client.delete_objects(bucket: bucket, delete: { objects: keys }) if keys.any?
          end

          private

          def object_key(record, name)
            "#{record.retention}/#{prefix}/#{record.key}/#{record.reference}/#{name}"
          end

          def get(record, name)
            client.get_object(
              bucket: record.bucket_name,
              key: object_key(record, name)
            ).body.read
          end
        end
      end
    end
  end
end
