# frozen_string_literal: true

RSpec.describe Trifle::Traces::Driver::Data::File do
  around do |example|
    Dir.mktmpdir do |dir|
      @root = dir
      example.run
    end
  end

  it_behaves_like 'a data driver' do
    let(:driver) { described_class.new(path: @root) }
  end

  it_behaves_like 'a data driver' do
    let(:driver) { described_class.new(path: @root, gzip: true) }
  end

  %i[live deferred].each do |mode|
    it "removes #{mode} attachment sources while preserving the filesystem copy" do
      source = File.join(@root, 'source.txt')
      File.write(source, 'report')
      driver = described_class.new(path: File.join(@root, 'storage'), gzip: true)
      config = Trifle::Traces::Configuration.new
      config.index_driver = Trifle::Traces::Driver::Index::Memory.new
      config.data_driver = driver
      config.bump_every = 0
      tracer = Trifle::Traces::Tracer::Hash.new(key: 'jobs/cleanup', config: config, mode: mode)
      tracer.artifact('public.txt', source)
      expect(File.exist?(source)).to be(true)
      tracer.wrapup

      expect(File.exist?(source)).to be(false)
      record = config.index_driver.find(tracer.reference)
      expect(driver.read_artifact(record, name: 'public.txt')).to eq('report')
    end
  end

  describe 'layout' do
    let(:driver) { described_class.new(path: @root) }
    let(:record) do
      Trifle::Traces::TraceRecord.new(
        reference: 'REF123', key: 'jobs/import', retention: 3, parts: 0, bucket_name: nil
      )
    end

    it 'stores parts under retention/key/reference' do
      driver.write_part(record, part: 1, entries: [{ message: 'hi' }])

      expect(File).to exist(File.join(@root, '3', 'jobs/import', 'REF123', 'data_1.json'))
    end

    it 'gzips parts when enabled' do
      gz = described_class.new(path: @root, gzip: true)
      gz.write_part(record, part: 1, entries: [{ message: 'hi' }])

      expect(File).to exist(File.join(@root, '3', 'jobs/import', 'REF123', 'data_1.json.gz'))
      expect(gz.read_part(record, part: 1).first[:message]).to eq('hi')
    end
  end

  describe '#cleanup!' do
    let(:driver) { described_class.new(path: @root) }
    let(:record) do
      Trifle::Traces::TraceRecord.new(
        reference: 'REF123', key: 'jobs/import', retention: 3, parts: 1, bucket_name: nil
      )
    end

    it 'removes trace directories older than their retention class' do
      driver.write_part(record, part: 1, entries: [{ message: 'hi' }])

      driver.cleanup!(now: Time.now + (4 * 86_400))

      expect { driver.read_part(record, part: 1) }.to raise_error(StandardError)
    end

    it 'keeps trace directories within retention' do
      driver.write_part(record, part: 1, entries: [{ message: 'hi' }])

      driver.cleanup!(now: Time.now + 86_400)

      expect(driver.read_part(record, part: 1).first[:message]).to eq('hi')
    end
  end
end
