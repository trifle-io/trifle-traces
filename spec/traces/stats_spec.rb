# frozen_string_literal: true

require 'trifle/stats'

RSpec.describe 'Native trace activity Stats' do
  let(:stats) do
    config = Trifle::Stats::Configuration.new
    config.driver = Trifle::Stats::Driver::Process.new
    config.granularities = %w[10m 1h]
    config.time_zone = 'GMT'
    config.buffer_enabled = false
    config
  end
  let(:config) do
    config = Trifle::Traces::Configuration.new
    config.index_driver = Trifle::Traces::Driver::Index::Memory.new
    config.data_driver = Trifle::Traces::Driver::Data::Memory.new
    config.stats_config = stats
    config.bump_every = 0
    config
  end

  def new_tracer(mode: :live)
    Trifle::Traces::Tracer::Hash.new(key: 'jobs/import/products', mode: mode, config: config)
  end

  def values(tracer, key: tracer.key, granularity: '10m')
    at = tracer.trace_record.last_at.getutc
    Trifle::Stats.values(key: key, from: at, to: at, granularity: granularity, config: stats)[:values].first
  end

  %i[live deferred].each do |mode|
    it "tracks finalized #{mode} traces once without changing user callbacks or reading the index" do
      callbacks = []
      config.on(:wrapup) { |tracer| callbacks << tracer.reference }
      allow(config.index_driver).to receive(:find).and_raise('unexpected index read')
      tracer = new_tracer(mode: mode)
      dispatcher = tracer.instance_variable_get(:@dispatcher)
      started_at = dispatcher.instance_variable_get(:@started_at)
      allow(dispatcher).to receive(:monotonic_now).and_return(started_at + 0.125)

      tracer.trace('working')
      tracer.warn!
      tracer.bump
      expect(values(tracer)).to eq({})
      tracer.wrapup

      stats.granularities.each do |granularity|
        expect(values(tracer, granularity: granularity)).to eq(
          'count' => 1, 'states' => { 'warning' => 1 }, 'entries' => { 'count' => 2 },
          'duration' => {
            'count' => 1, 'sum' => 125, 'square' => 15_625,
            'states' => { 'warning' => { 'count' => 1, 'sum' => 125, 'square' => 15_625 } }
          }
        )
      end
      expect(values(tracer, key: 'jobs')).to eq({})
      expect(callbacks).to eq([tracer.reference])
    end

    it "skips ignored #{mode} traces" do
      tracer = new_tracer(mode: mode)
      tracer.ignore!
      tracer.wrapup
      expect(values(tracer)).to eq({})
    end
  end

  it 'is disabled by default even when global Stats exists' do
    config.stats_config = nil
    expect(Trifle::Stats).not_to receive(:track)
    new_tracer.wrapup
  end

  it 'supports Stats without persistence while preserving callback data' do
    config.index_driver = nil
    config.data_driver = nil
    tracer = new_tracer(mode: :deferred)
    tracer.trace('working')
    tracer.wrapup
    expect(values(tracer)['count']).to eq(1)
    expect(values(tracer)['entries']['count']).to eq(tracer.data.length)
    expect(tracer.data.length).to eq(2)
  end

  it 'does not emit for failed persistence but emits once after a successful retry' do
    tracer = new_tracer(mode: :deferred)
    allow(config.index_driver).to receive(:create).and_raise('storage unavailable')
    expect { tracer.wrapup }.to raise_error('storage unavailable')
    expect(values(tracer)).to eq({})
    allow(config.index_driver).to receive(:create).and_call_original
    tracer.wrapup
    expect(values(tracer)['count']).to eq(1)
  end

  it 'does not emit twice when wrapup is retried after a user callback failure' do
    config.on(:wrapup) { raise 'callback failed' }
    tracer = new_tracer(mode: :deferred)
    expect { tracer.wrapup }.to raise_error('callback failed')
    config.callbacks[:wrapup].clear
    tracer.wrapup
    expect(values(tracer)['count']).to eq(1)
  end

  it 'logs Stats failures without failing persistence or skipping user callbacks' do
    callback = double('callback')
    config.on(:wrapup) { callback.call }
    allow(Trifle::Stats).to receive(:track).and_raise('stats unavailable')
    expect(callback).to receive(:call).once
    tracer = new_tracer(mode: :deferred)
    expect { tracer.wrapup }.to output(/stats tracking failed.*stats unavailable/).to_stderr
    expect(config.index_driver.find(tracer.reference).state).to eq(:success)
  end
end
