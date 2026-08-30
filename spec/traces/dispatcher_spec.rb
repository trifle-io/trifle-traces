# frozen_string_literal: true

RSpec.describe Trifle::Traces::Dispatcher do
  let(:index_driver) { Trifle::Traces::Driver::Index::Memory.new }
  let(:data_driver) { Trifle::Traces::Driver::Data::Memory.new }
  let(:config) do
    config = Trifle::Traces::Configuration.new
    config.index_driver = index_driver
    config.data_driver = data_driver
    config.bump_every = 0
    config.retention = 3
    config.context = ->(t) { { 'tenant' => t.meta&.first } }
    config
  end

  def tracer_for(mode: :live, **kwargs)
    Trifle::Traces::Tracer::Hash.new(key: 'jobs/import/products', meta: [42], mode: mode, config: config, **kwargs)
  end

  describe 'live mode' do
    it 'creates the index entry and part 1 at liftoff' do
      tracer = tracer_for

      record = index_driver.find(tracer.reference)
      expect(record.state).to eq(:running)
      expect(record.parts).to eq(1)
      expect(record.length).to eq(1)
      expect(record.context).to eq('tenant' => 42)
      expect(record.duration).to be_a(Integer)
      expect(record.counters).to eq(
        states: { success: 1, warning: 0, error: 0, debug: 0 },
        types: { text: 1, head: 0, raw: 0, media: 0 },
        max_level: 0
      )
      expect(record.retention).to eq(3)
      expect(record.expires_at.to_i).to eq(record.first_at.to_i + (3 * 86_400))
      expect(data_driver.read_part(record, part: 1).first[:message]).to include('initialized')
    end

    it 'flushes numbered parts and updates the index on bump' do
      tracer = tracer_for
      tracer.trace('first step')
      tracer.trace('second step')

      record = index_driver.find(tracer.reference)
      expect(record.parts).to eq(3)
      expect(record.length).to eq(3)
      expect(data_driver.read_part(record, part: 2).first[:message]).to eq('first step')
    end

    it 'finalizes state, tags and totals at wrapup' do
      tracer = tracer_for
      tracer.tag('invoice:1')
      tracer.warn!
      tracer.wrapup

      record = index_driver.find(tracer.reference)
      expect(record.state).to eq(:warning)
      expect(record.tags).to eq(['invoice:1'])
      expect(data_driver.read(record).count).to eq(record.length)
    end

    it 'updates duration from the monotonic clock during bumps and wrapup' do
      tracer = tracer_for
      dispatcher = tracer.instance_variable_get(:@dispatcher)
      started_at = dispatcher.instance_variable_get(:@started_at)

      allow(dispatcher).to receive(:monotonic_now).and_return(started_at + 0.125)
      tracer.trace('timed step')
      expect(index_driver.find(tracer.reference).duration).to eq(125)

      allow(dispatcher).to receive(:monotonic_now).and_return(started_at + 0.5)
      tracer.wrapup
      expect(index_driver.find(tracer.reference).duration).to eq(500)
    end

    it 'deletes index and data when ignored' do
      tracer = tracer_for
      tracer.trace('work')
      tracer.ignore!
      tracer.wrapup

      expect(index_driver.find(tracer.reference)).to be_nil
      expect(data_driver.parts[tracer.reference]).to be_empty
    end

    it 'raises at liftoff when the index driver cannot update' do
      allow(index_driver).to receive(:capabilities).and_return(
        { update: false, delete: true, search: true, ttl: :none }
      )

      expect { tracer_for }.to raise_error(Trifle::Traces::Error, /deferred/)
    end
  end

  describe 'deferred mode' do
    it 'performs zero writes before wrapup' do
      tracer = tracer_for(mode: :deferred)
      tracer.trace('step one')

      expect(index_driver.records).to be_empty
      expect(data_driver.parts).to be_empty
      expect(tracer.reference).not_to be_nil
    end

    it 'writes exactly one part and one index entry at wrapup' do
      tracer = tracer_for(mode: :deferred)
      tracer.trace('step one')
      tracer.trace('step two')
      tracer.wrapup

      record = index_driver.find(tracer.reference)
      expect(record.state).to eq(:success)
      expect(record.parts).to eq(1)
      expect(record.length).to eq(3)
      expect(data_driver.read(record).count).to eq(3)
    end

    it 'records final duration from the monotonic clock' do
      tracer = tracer_for(mode: :deferred)
      dispatcher = tracer.instance_variable_get(:@dispatcher)
      started_at = dispatcher.instance_variable_get(:@started_at)
      allow(dispatcher).to receive(:monotonic_now).and_return(started_at + 1.234)

      tracer.wrapup

      expect(index_driver.find(tracer.reference).duration).to eq(1_234)
    end

    it 'aggregates entry states, types and maximum nesting level' do
      tracer = tracer_for(mode: :deferred)
      tracer.trace('warning head', state: :warning, head: true)
      tracer.trace('outer') do
        tracer.trace('nested debug', state: :debug)
        'result'
      end
      tracer.trace('failure', state: :error)
      tracer.wrapup

      record = index_driver.find(tracer.reference)
      expect(record.counters).to eq(
        states: { success: 4, warning: 1, error: 1, debug: 1 },
        types: { text: 5, head: 1, raw: 1, media: 0 },
        max_level: 1
      )
      expect(record.counters[:states].values.sum).to eq(record.length)
      expect(record.counters[:types].values.sum).to eq(record.length)
    end

    it 'writes nothing when ignored' do
      tracer = tracer_for(mode: :deferred)
      tracer.trace('step one')
      tracer.ignore!
      tracer.wrapup

      expect(index_driver.records).to be_empty
      expect(data_driver.parts).to be_empty
    end
  end

  describe 'oversize offload' do
    it 'replaces oversized messages with media entries backed by artifacts' do
      config.payload_size_limit = 16
      tracer = tracer_for(mode: :deferred)
      tracer.trace('x' * 100)
      tracer.wrapup

      record = index_driver.find(tracer.reference)
      offloaded = data_driver.read(record).find { |e| e[:size] == 100 }
      expect(offloaded[:type]).to eq(:media)
      expect(record.counters[:types]).to include(text: 0, media: 2)
      expect(data_driver.read_artifact(record, name: offloaded[:message])).to eq('x' * 100)
    end
  end

  describe 'artifact uploads' do
    it 'uploads files recorded via tracer.artifact' do
      tracer = tracer_for
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'report.csv')
        File.write(path, 'a,b')
        tracer.artifact('report', path)
        tracer.wrapup

        record = index_driver.find(tracer.reference)
        expect(data_driver.read_artifact(record, name: 'report.csv')).to eq('a,b')
      end
    end
  end

  describe 'error handling' do
    it 're-queues entries when a bump flush fails and recovers on the next flush' do
      calls = 0
      allow(data_driver).to receive(:write_part).and_wrap_original do |original, *args, **kwargs|
        calls += 1
        raise 'transient storage error' if calls == 2 # part 1 succeeds, first bump fails

        original.call(*args, **kwargs)
      end

      warnings = []
      config.error_handler = ->(error, _tracer, phase) { warnings << [phase, error.message] }

      tracer = tracer_for
      tracer.trace('lost?')
      expect(index_driver.find(tracer.reference).counters[:states][:success]).to eq(1)
      tracer.trace('recovered')

      record = index_driver.find(tracer.reference)
      messages = data_driver.read(record).map { |e| e[:message] }
      expect(messages).to include('lost?', 'recovered')
      expect(record.length).to eq(3)
      expect(record.counters[:states][:success]).to eq(3)
      expect(record.counters[:states].values.sum).to eq(record.length)
      expect(warnings.map(&:first)).to eq([:bump])
    end

    it 'raises wrapup persistence failures by default' do
      tracer = tracer_for
      allow(data_driver).to receive(:write_part).and_raise('storage down')
      tracer.trace('boom') # bump warns but does not raise

      expect { tracer.wrapup }.to raise_error('storage down')
    end
  end
end
