# frozen_string_literal: true

RSpec.describe Trifle::Traces::Middleware::Sidekiq do
  let(:worker_class) { Class.new }
  let(:worker) { worker_class.new }
  let(:job) { { 'tracer_key' => 'commodity/calculate/one', 'args' => [42] } }
  let(:config) { Trifle::Traces.default }

  before do
    config.index_driver = Trifle::Traces::Driver::Index::Memory.new
    config.data_driver = Trifle::Traces::Driver::Data::Memory.new
    allow(worker_class).to receive(:get_sidekiq_options).and_return('tracer_mode' => :deferred)
  end

  it 'uses worker defaults for jobs queued before the mode was configured' do
    tracer = nil
    described_class.new.call(worker, job, 'calculator') do
      tracer = Trifle::Traces.tracer
      tracer.trace('calculated')
      expect(tracer.mode).to eq(:deferred)
      expect(config.index_driver.find(tracer.reference)).to be_nil
    end

    expect(config.index_driver.find(tracer.reference).state).to eq(:success)
    expect(tracer.trace_record.parts).to eq(1)
  end

  it 'honors an explicit queued mode ahead of the worker default' do
    tracer = described_class.new.tracer_for(job: job.merge('tracer_mode' => 'live'), worker: worker)
    expect(tracer.mode).to eq(:live)
    expect(config.index_driver.find(tracer.reference)).not_to be_nil
    tracer.wrapup
  end

  it 'uses the configured default when the worker has no Sidekiq options' do
    tracer = described_class.new.tracer_for(job: job, worker: Object.new)
    expect(tracer.mode).to eq(:live)
    tracer.wrapup
  end

  it 'does not trace jobs without a tracer key' do
    expect(described_class.new.tracer_for(job: { 'args' => [] }, worker: worker)).to be_nil
  end
end
