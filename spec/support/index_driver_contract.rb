# frozen_string_literal: true

# Shared contract every index driver must satisfy. Include with:
#   it_behaves_like 'an index driver' do
#     let(:driver) { ... }
#   end
RSpec.shared_examples 'an index driver' do
  def build_record(reference:, key: 'jobs/import/products', state: :running, tags: [], at: Time.now)
    Trifle::Traces::TraceRecord.new(
      reference: reference, key: key, state: state, tags: tags,
      meta: %w[42 shopify], context: { 'tenant_id' => 42 },
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
      record.length = 9
      record.parts = 3
      driver.update(record)

      found = driver.find(record.reference)
      expect(found.state).to eq(:error)
      expect(found.tags).to eq(%w[failed])
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

      [
        { key: 'jobs/import/products', state: :success, tags: %w[tenant:1] },
        { key: 'jobs/import/orders', state: :error, tags: %w[tenant:2 failed] },
        { key: 'jobs/export/orders', state: :success, tags: %w[tenant:1] }
      ].each do |attrs|
        driver.create(build_record(reference: driver.generate_reference, **attrs))
      end
    end

    it 'matches key-path prefixes via segment' do
      next unless driver.capabilities[:search]

      result = driver.search(segment: 'jobs/import')
      expect(result[:traces].map(&:key)).to contain_exactly('jobs/import/products', 'jobs/import/orders')
    end

    it 'matches any tag' do
      next unless driver.capabilities[:search]

      result = driver.search(tags: %w[tenant:1])
      expect(result[:traces].count).to eq(2)
    end

    it 'filters by state' do
      next unless driver.capabilities[:search]

      result = driver.search(state: :error)
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
  end
end
