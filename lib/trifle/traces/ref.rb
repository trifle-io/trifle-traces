# frozen_string_literal: true

require 'securerandom'

module Trifle
  module Traces
    # Generates monotonic ULID-style references: 48 bits of millisecond
    # timestamp followed by 80 bits of randomness, Crockford base32
    # encoded. Lexicographic order equals generation order (references
    # created within the same millisecond increment the random part), so
    # index drivers can rely on `reference DESC` for newest-first.
    module Ref
      ENCODING = '0123456789ABCDEFGHJKMNPQRSTVWXYZ'
      RANDOM_MASK = (1 << 80) - 1

      @mutex = Mutex.new
      @last_at_ms = 0
      @last_random = 0

      def self.generate(at: Time.now)
        @mutex.synchronize do
          at_ms = (at.to_f * 1000).to_i
          if at_ms > @last_at_ms
            @last_at_ms = at_ms
            @last_random = SecureRandom.random_number(1 << 80)
          else
            @last_random = (@last_random + 1) & RANDOM_MASK
          end

          encode((@last_at_ms << 80) | @last_random)
        end
      end

      def self.encode(value)
        26.downto(1).map do |i|
          ENCODING[(value >> ((i - 1) * 5)) & 0x1F]
        end.join
      end
    end
  end
end
