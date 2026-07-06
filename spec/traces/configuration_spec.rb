# frozen_string_literal: true

RSpec.describe Trifle::Traces::Configuration do
  subject(:config) { described_class.new }

  it 'defaults to Null drivers so tracing works without persistence' do
    expect(config.index_driver).to be_a(Trifle::Traces::Driver::Index::Null)
    expect(config.data_driver).to be_a(Trifle::Traces::Driver::Data::Null)
  end

  it 'has production-shaped defaults' do
    expect(config.bump_every).to eq(15)
    expect(config.default_mode).to eq(:live)
    expect(config.payload_size_limit).to eq(100 * 1024)
    expect(config.retention).to eq(7)
  end

  describe '#context_for and #retention_for' do
    let(:tracer) { double('tracer', meta: [42]) }

    it 'resolves static values' do
      config.retention = 30

      expect(config.retention_for(tracer)).to eq(30)
      expect(config.context_for(tracer)).to eq({})
    end

    it 'resolves callables with the tracer' do
      config.context = ->(t) { { 'tenant' => t.meta.first } }
      config.retention = ->(_t) { 3 }

      expect(config.context_for(tracer)).to eq('tenant' => 42)
      expect(config.retention_for(tracer)).to eq(3)
    end
  end

  describe '#error_handler default' do
    it 'raises for liftoff and wrapup, warns for bump' do
      error = RuntimeError.new('boom')

      expect { config.error_handler.call(error, nil, :liftoff) }.to raise_error('boom')
      expect { config.error_handler.call(error, nil, :wrapup) }.to raise_error('boom')
      expect { config.error_handler.call(error, nil, :bump) }.to output(/will retry/).to_stderr
    end
  end

  describe '#on' do
    it 'registers callbacks per event' do
      config.on(:wrapup) { |t| t }

      expect(config.callbacks[:wrapup].count).to eq(1)
    end
  end
end
