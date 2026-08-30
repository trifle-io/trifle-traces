# frozen_string_literal: true

# Shared contract every index driver must satisfy. Include with:
#   it_behaves_like 'an index driver' do
#     let(:driver) { ... }
#   end
RSpec.shared_examples 'an index driver' do
  def build_record(reference:, key: 'jobs/import/products', state: :running, tags: [],
                   duration: 100, at: Time.now)
    Trifle::Traces::TraceRecord.new(
      reference: reference, key: key, state: state, tags: tags,
      meta: %w[42 shopify], context: { 'tenant_id' => 42 },
      duration: duration,
      counters: {
        states: { success: 1, warning: 0, error: 0, debug: 0 },
        types: { text: 1, head: 0, raw: 0, media: 0 },
        max_level: 0
      },
      length: 1, parts: 1, first_at: at, last_at: at,
      retention: 3, expires_at: at + (3 * 86_400), bucket_id: 0
    )
  end

  describe '#generate_reference' do
    it 'returns unique, time-sortable references without I/O' do
      first = driver.generate_reference
      second = driver.generate_reference

      expect(first).not_to eq(second)
      expect(first).to be < second
    end
  end

  describe '#capabilities' do
    it 'declares the full capability set' do
      expect(driver.capabilities.keys).to include(:update, :delete, :search, :ttl)
    end
  end

  describe '#create and #find' do
    it 'round-trips a record' do
      record = build_record(reference: driver.generate_reference)
      driver.create(record)

      found = driver.find(record.reference)

      expect(found.reference).to eq(record.reference)
      expect(found.key).to eq('jobs/import/products')
      expect(found.state).to eq(:running)
      expect(found.meta).to eq(%w[42 shopify])
      expect(found.duration).to eq(100)
      expect(found.counters).to eq(record.counters)
      expect(found.length).to eq(1)
      expect(found.parts).to eq(1)
      expect(found.retention).to eq(3)
      expect(found.bucket_id).to eq(0)
      expect(found.first_at.to_i).to eq(record.first_at.to_i)
      expect(found.expires_at.to_i).to eq(record.expires_at.to_i)
    end

    it 'returns nil for unknown references' do
      expect(driver.find(driver.generate_reference)).to be_nil
    end
  end

  describe '#update' do
    it 'persists mutable fields' do
      next unless driver.capabilities[:update]

      record = build_record(reference: driver.generate_reference)
      driver.create(record)

      record.state = :error
      record.tags = %w[failed]
      record.duration = 1_250
      record.counters = {
        states: { success: 5, warning: 1, error: 2, debug: 1 },
        types: { text: 6, head: 1, raw: 1, media: 1 },
        max_level: 3
      }
      record.length = 9
      record.parts = 3
      driver.update(record)

      found = driver.find(record.reference)
      expect(found.state).to eq(:error)
      expect(found.tags).to eq(%w[failed])
      expect(found.duration).to eq(1_250)
      expect(found.counters).to eq(record.counters)
      expect(found.length).to eq(9)
      expect(found.parts).to eq(3)
    end
  end

  describe '#delete' do
    it 'removes the record' do
      next unless driver.capabilities[:delete]

      record = build_record(reference: driver.generate_reference)
      driver.create(record)
      driver.delete(record.reference)

      expect(driver.find(record.reference)).to be_nil
    end
  end

  describe '#search' do
    before do
      next unless driver.capabilities[:search]

      @search_start = Time.utc(2026, 8, 30, 10, 0, 0)
      [
        { key: 'jobs/import/products', state: :success, tags: %w[tenant:1], duration: 100 },
        { key: 'jobs/import/orders', state: :error, tags: %w[tenant:2 failed], duration: 5_000 },
        { key: 'jobs/export/orders', state: :success, tags: %w[tenant:1], duration: 10_000 }
      ].each_with_index do |attrs, index|
        driver.create(
          build_record(reference: driver.generate_reference, at: @search_start + index, **attrs)
        )
      end
    end

    it 'matches key-path prefixes via segment' do
      next unless driver.capabilities[:search]

      result = driver.search(segment: 'jobs/import')
      expect(result[:traces].map(&:key)).to contain_exactly('jobs/import/products', 'jobs/import/orders')
    end

    it 'matches any tag' do
      next unless driver.capabilities[:search]

      result = driver.search(tags: { any: %w[tenant:1] })
      expect(result[:traces].count).to eq(2)
    end

    it 'combines tag any and all groups' do
      next unless driver.capabilities[:search]

      result = driver.search(tags: { any: %w[tenant:1 tenant:2], all: %w[tenant:2 failed] })
      expect(result[:traces].map(&:key)).to eq(['jobs/import/orders'])
    end

    it 'ignores empty tag groups' do
      next unless driver.capabilities[:search]

      result = driver.search(tags: { any: [], all: [] })
      expect(result[:traces].count).to eq(3)
    end

    it 'rejects legacy tag shorthand' do
      next unless driver.capabilities[:search]

      expect { driver.search(tags: 'tenant:1') }.to raise_error(ArgumentError)
      expect { driver.search(tags: %w[tenant:1]) }.to raise_error(ArgumentError)
    end

    it 'filters by state' do
      next unless driver.capabilities[:search]

      result = driver.search(state: :error)
      expect(result[:traces].map(&:key)).to eq(['jobs/import/orders'])
    end

    it 'filters by inclusive start and exclusive end timestamps' do
      next unless driver.capabilities[:search]

      result = driver.search(from: @search_start + 1, to: @search_start + 2)
      expect(result[:traces].map(&:key)).to eq(['jobs/import/orders'])
    end

    it 'filters by inclusive minimum duration' do
      next unless driver.capabilities[:search]

      result = driver.search(duration_min: 5_000)
      expect(result[:traces].map(&:key)).to eq(['jobs/export/orders', 'jobs/import/orders'])
    end

    it 'combines segment, tags, state, time and duration filters' do
      next unless driver.capabilities[:search]

      result = driver.search(
        segment: 'jobs/import', tags: { all: %w[failed] }, state: :error,
        from: @search_start, to: @search_start + 3, duration_min: 5_000
      )
      expect(result[:traces].map(&:key)).to eq(['jobs/import/orders'])
    end

    it 'returns newest-first and paginates with an opaque cursor' do
      next unless driver.capabilities[:search]

      page = driver.search(segment: 'jobs', limit: 2)
      expect(page[:traces].count).to eq(2)
      expect(page[:traces].first.key).to eq('jobs/export/orders')
      expect(page[:cursor]).not_to be_nil

      rest = driver.search(segment: 'jobs', limit: 2, cursor: page[:cursor])
      expect(rest[:traces].map(&:key)).to eq(['jobs/import/products'])
    end

    it 'paginates deterministically when timestamps are equal' do
      next unless driver.capabilities[:search]

      tied_at = @search_start + 10
      references = 3.times.map do |index|
        reference = driver.generate_reference
        driver.create(
          build_record(reference: reference, key: "tied/#{index}", at: tied_at)
        )
        reference
      end

      first = driver.search(segment: 'tied', limit: 2)
      second = driver.search(segment: 'tied', limit: 2, cursor: first[:cursor])

      expect((first[:traces] + second[:traces]).map(&:reference)).to eq(references.reverse)
      expect(second[:cursor]).to be_nil
    end
  end
end
