# frozen_string_literal: true

require 'json'
require 'zlib'
require 'stringio'

module Trifle
  module Traces
    module Driver
      module Data
        # Shared payload (de)serialization for data drivers.
        module Encoding
          def pack_entries(entries)
            body = JSON.generate(entries)
            gzip? ? gzip(body) : body
          end

          def unpack_entries(body)
            body = gunzip(body) if gzip?
            JSON.parse(body, symbolize_names: true).map do |entry|
              entry[:state] = entry[:state]&.to_sym
              entry[:type] = entry[:type]&.to_sym
              entry
            end
          end

          def part_name(part)
            "data_#{part}.json#{'.gz' if gzip?}"
          end

          def gzip?
            @gzip == true
          end

          def gzip(body)
            io = StringIO.new
            writer = Zlib::GzipWriter.new(io)
            writer.write(body)
            writer.close
            io.string
          end

          def gunzip(body)
            Zlib::GzipReader.new(StringIO.new(body)).read
          end
        end
      end
    end
  end
end
