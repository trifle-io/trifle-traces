# frozen_string_literal: true

RSpec.describe Trifle::Traces::Tracer::Hash do
  let(:config) do
    config = Trifle::Traces::Configuration.new
    config.bump_every = 3600 # keep bump quiet unless a spec wants it
    config
  end

  def build_tracer(**kwargs)
    described_class.new(key: 'jobs/import/products', config: config, **kwargs)
  end

  describe '#initialize' do
    it 'gets its reference from the index driver' do
      tracer = build_tracer

      expect(tracer.reference).to be_a(String)
      expect(tracer.reference.length).to eq(26)
    end

    it 'prefers an explicitly passed reference' do
      tracer = build_tracer(reference: 'custom-ref')

      expect(tracer.reference).to eq('custom-ref')
    end

    it 'defaults mode from configuration' do
      config.default_mode = :deferred

      expect(build_tracer.mode).to eq(:deferred)
    end

    it 'accepts mode as a string' do
      expect(build_tracer(mode: 'deferred').mode).to eq(:deferred)
    end

    it 'records an initialization line' do
      tracer = build_tracer

      expect(tracer.data.first[:message]).to include('Tracer has been initialized')
    end
  end

  describe '#keys' do
    it 'returns cumulative path prefixes' do
      expect(build_tracer.keys).to eq(%w[jobs jobs/import jobs/import/products])
    end
  end

  describe '#trace' do
    it 'records plain messages' do
      tracer = build_tracer
      tracer.trace('hello')

      entry = tracer.data.last
      expect(entry[:message]).to eq('hello')
      expect(entry[:type]).to eq(:text)
      expect(entry[:state]).to eq(:success)
      expect(entry[:level]).to eq(0)
    end

    it 'records head and custom state entries' do
      tracer = build_tracer
      tracer.trace('section', head: true, state: :error)

      expect(tracer.data.last[:type]).to eq(:head)
      expect(tracer.data.last[:state]).to eq(:error)
    end

    it 'nests block traces with levels and serialized results' do
      tracer = build_tracer
      result = tracer.trace('outer') do
        tracer.trace('inner')
        42
      end

      expect(result).to eq(42)
      inner = tracer.data.find { |e| e[:message] == 'inner' }
      expect(inner[:level]).to eq(1)
      expect(tracer.data.last[:message]).to include('42')
      expect(tracer.data.last[:type]).to eq(:raw)
      expect(tracer.level).to eq(0)
    end

    it 'marks the closing line as error and re-raises when the block raises' do
      tracer = build_tracer

      expect { tracer.trace('boom') { raise ArgumentError, 'nope' } }.to raise_error(ArgumentError)
      expect(tracer.data.last(2).first[:state]).to eq(:error)
      expect(tracer.level).to eq(0)
    end

    it 'falls back to the inspect serializer when the configured one raises' do
      broken = Class.new do
        def sanitize(_payload)
          raise 'broken serializer'
        end
      end
      config.serializer_class = broken

      tracer = build_tracer
      tracer.trace('block') { { answer: 42 } }

      expect(tracer.data.last[:message]).to include('{:answer=>42}')
    end
  end

  describe 'state helpers' do
    it 'transitions state via fail!, warn! and success!' do
      tracer = build_tracer
      expect(tracer.running?).to be true

      tracer.fail!
      expect(tracer.state).to eq(:error)
      tracer.warn!
      expect(tracer.state).to eq(:warning)
      tracer.success!
      expect(tracer.success?).to be true
    end

    it 'marks success at wrapup when still running' do
      tracer = build_tracer
      tracer.wrapup

      expect(tracer.state).to eq(:success)
    end

    it 'flags ignore' do
      tracer = build_tracer
      tracer.ignore!

      expect(tracer.ignore).to be true
    end
  end

  describe '#bump throttling' do
    it 'does not fire callbacks before bump_every elapses' do
      fired = []
      config.bump_every = 3600
      config.on(:bump) { |_t| fired << true }

      tracer = build_tracer
      tracer.trace('one')

      expect(fired).to be_empty
    end

    it 'fires callbacks when bump_every is zero' do
      fired = []
      config.bump_every = 0
      config.on(:bump) { |_t| fired << true }

      tracer = build_tracer
      tracer.trace('one')

      expect(fired.count).to eq(1)
    end
  end

  describe 'user callbacks' do
    it 'fires liftoff and wrapup callbacks with the tracer' do
      seen = []
      config.on(:liftoff) { |t| seen << [:liftoff, t.key] }
      config.on(:wrapup) { |t| seen << [:wrapup, t.state] }

      tracer = build_tracer
      tracer.wrapup

      expect(seen).to eq([[:liftoff, 'jobs/import/products'], [:wrapup, :success]])
    end

    it 'does not use callback return values as the reference' do
      config.on(:liftoff) { |_t| 'not-a-reference' }

      expect(build_tracer.reference).not_to eq('not-a-reference')
    end
  end

  describe '#artifact' do
    it 'records a media entry and remembers the path' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'report.csv')
        File.write(path, 'a,b')

        tracer = build_tracer
        tracer.artifact('report', path)

        expect(tracer.data.last[:type]).to eq(:media)
        expect(tracer.data.last[:size]).to eq(3)
        expect(tracer.artifacts).to eq([path])
        expect(tracer.pop_all_artifacts).to eq([{ name: 'report', path: path }])
      end
    end
  end
end
