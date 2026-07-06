# frozen_string_literal: true

require 'fileutils'
require_relative 'encoding'

module Trifle
  module Traces
    module Driver
      module Data
        # Local filesystem payload storage. Same directory layout as the
        # S3 driver ("<retention>/<key>/<reference>/"), so cleanup! can
        # expire whole retention prefixes.
        class File
          include Encoding

          attr_accessor :path

          def initialize(path:, gzip: false)
            @path = path
            @gzip = gzip
          end

          def self.setup!(path:)
            FileUtils.mkdir_p(path)
          end

          def description
            self.class.name
          end

          def generate_bucket_id
            0
          end

          def write_part(record, part:, entries:)
            write(record, part_name(part), pack_entries(entries))
          end

          def write_artifact(record, name:, payload: nil, path: nil)
            body = payload || ::File.binread(path)
            write(record, ::File.join('artifacts', name), body)
            name
          end

          def read_part(record, part:)
            unpack_entries(::File.binread(file_path(record, part_name(part))))
          end

          def read(record)
            (1..record.parts.to_i).flat_map { |part| read_part(record, part: part) }
          end

          def read_artifact(record, name:)
            ::File.binread(file_path(record, ::File.join('artifacts', name)))
          end

          def delete(record)
            FileUtils.rm_rf(trace_dir(record))
          end

          # Removes trace directories older than their retention class.
          # Run periodically (cron); the retention days are encoded as
          # the top-level directory name.
          def cleanup!(now: Time.now)
            Dir.glob(::File.join(path, '*')).each do |retention_dir|
              days = ::File.basename(retention_dir).to_i
              next if days <= 0

              Dir.glob(::File.join(retention_dir, '**/*/')).each do |dir|
                next unless ::File.exist?(dir) # parent may already be gone

                FileUtils.rm_rf(dir) if ::File.mtime(dir) < now - (days * 86_400)
              end
            end
          end

          private

          def trace_dir(record)
            ::File.join(path, record.retention.to_s, record.key.to_s, record.reference.to_s)
          end

          def file_path(record, name)
            ::File.join(trace_dir(record), name)
          end

          def write(record, name, body)
            target = file_path(record, name)
            FileUtils.mkdir_p(::File.dirname(target))
            ::File.binwrite(target, body)
          end
        end
      end
    end
  end
end
