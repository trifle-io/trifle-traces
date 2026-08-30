# frozen_string_literal: true

RSpec.describe 'Trifle::Traces read API' do
  let(:config) do
    config = Trifle::Traces::Configuration.new
    config.index_driver = Trifle::Traces::Driver::Index::Memory.new
    config.data_driver = Trifle::Traces::Driver::Data::Memory.new
    config.bump_every = 0
    config
  end

  before do
    tracer = Trifle::Traces::Tracer::Hash.new(key: 'jobs/import/products', config: config)
    tracer.tag('tenant:1')
    tracer.trace('working')
    tracer.wrapup
    @reference = tracer.reference
  end

  describe '.find' do
    it 'returns the trace record' do
      record = Trifle::Traces.find(@reference, config: config)

      expect(record.key).to eq('jobs/import/products')
      expect(record.state).to eq(:success)
      expect(record.duration).to be_a(Integer)
      expect(record.counters[:states].values.sum).to eq(record.length)
    end
  end

  describe '.search' do
    it 'searches through the index driver' do
      result = Trifle::Traces.search(
        segment: 'jobs/import', tags: { all: %w[tenant:1] }, duration_min: 0,
        from: Time.at(0), to: Time.now + 1, config: config
      )

      expect(result[:traces].map(&:reference)).to eq([@reference])
    end

    it 'rejects legacy scalar and array tag shorthand' do
      expect do
        Trifle::Traces.search(tags: 'tenant:1', config: config)
      end.to raise_error(ArgumentError)

      expect do
        Trifle::Traces.search(tags: %w[tenant:1], config: config)
      end.to raise_error(ArgumentError)
    end
  end

  describe '.payload' do
    it 'reads all parts through the data driver' do
      record = Trifle::Traces.find(@reference, config: config)
      entries = Trifle::Traces.payload(record, config: config)

      expect(entries.map { |e| e[:message] }).to include('working')
      expect(entries.count).to eq(record.length)
    end
  end
end
