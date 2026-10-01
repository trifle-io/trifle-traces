# frozen_string_literal: true

require 'stringio'

RSpec.describe Trifle::Traces::Driver::Data::S3 do
  describe 'recorded bucket names' do
    let(:objects) { {} }
    let(:client) do
      double('S3 client').tap do |s3|
        allow(s3).to receive(:put_object) do |bucket:, key:, body:|
          objects[[bucket, key]] = body.respond_to?(:read) ? body.read : body
        end
        allow(s3).to receive(:get_object) do |bucket:, key:|
          double(body: StringIO.new(objects.fetch([bucket, key])))
        end
        allow(s3).to receive(:list_objects_v2) do |bucket:, prefix:|
          keys = objects.keys.select { |stored_bucket, key| stored_bucket == bucket && key.start_with?(prefix) }
          double(contents: keys.map { |_stored_bucket, key| double(key: key) })
        end
        allow(s3).to receive(:delete_objects) do |bucket:, delete:|
          delete[:objects].each { |object| objects.delete([bucket, object[:key]]) }
        end
      end
    end
    let(:driver) { described_class.new(client: client, buckets: ['selected-traces']) }
    let(:index) { Trifle::Traces::Driver::Index::Memory.new }
    let(:config) do
      Trifle::Traces::Configuration.new.tap do |configuration|
        configuration.index_driver = index
        configuration.data_driver = driver
        configuration.bump_every = 0
      end
    end

    %i[live deferred].each do |mode|
      it "removes local files after #{mode} wrapup while keeping S3 artifacts readable" do
        Dir.mktmpdir do |dir|
          path = File.join(dir, 'report.txt')
          File.write(path, 'report')
          tracer = Trifle::Traces::Tracer::Hash.new(key: 'jobs/cleanup', config: config, mode: mode)
          Trifle::Traces.tracer = tracer
          Trifle::Traces.artifact('public.txt', path)
          expect(File.exist?(path)).to be(true)
          tracer.wrapup

          expect(File.exist?(path)).to be(false)
          expect(driver.read_artifact(index.find(tracer.reference), name: 'public.txt')).to eq('report')
        end
      end

      it "keeps #{mode} traces in their recorded bucket after bucket lists change" do
        expect(driver).to receive(:generate_bucket_name).once.and_call_original
        tracer = Trifle::Traces::Tracer::Hash.new(key: 'jobs/bucket-name', config: config, mode: mode)

        driver.buckets = %w[replacement-traces selected-traces]
        tracer.trace('after reordering')
        driver.buckets = ['replacement-traces']
        tracer.trace('after removal')
        tracer.wrapup

        record = index.find(tracer.reference)
        expect(record.bucket_name).to eq('selected-traces')
        expect(driver.read(record).map { |entry| entry[:message] })
          .to include('after reordering', 'after removal')

        driver.write_artifact(record, name: 'report.txt', payload: 'report')
        expect(driver.read_artifact(record, name: 'report.txt')).to eq('report')
        expect(objects.keys.map(&:first).uniq).to eq(['selected-traces'])

        driver.delete(record)
        expect(objects).to be_empty
      end
    end
  end

  endpoint = ENV['S3_ENDPOINT']

  if endpoint
    describe 'S3 endpoint integration' do
      require 'aws-sdk-s3'

      let(:client) do
        Aws::S3::Client.new(
          endpoint: endpoint,
          access_key_id: ENV.fetch('S3_ACCESS_KEY_ID', 'trifle'),
          secret_access_key: ENV.fetch('S3_SECRET_ACCESS_KEY', 'trifle-secret'),
          region: 'us-east-1',
          force_path_style: true
        )
      end
      let(:buckets) { %w[trifle-traces-spec-a trifle-traces-spec-b] }

      before(:each) do
        buckets.each do |bucket|
          client.create_bucket(bucket: bucket)
        rescue Aws::S3::Errors::BucketAlreadyOwnedByYou
          nil
        end
      end

      it_behaves_like 'a data driver' do
        let(:driver) { described_class.new(client: client, buckets: buckets) }
      end

      it_behaves_like 'a data driver' do
        let(:driver) { described_class.new(client: client, buckets: buckets, gzip: true) }
      end

      %i[live deferred].each do |mode|
        it "keeps uploaded #{mode} artifacts readable after removing their local sources" do
          Dir.mktmpdir do |dir|
            path = File.join(dir, 'report.txt')
            File.write(path, 'report')
            driver = described_class.new(client: client, buckets: buckets, gzip: true)
            config = Trifle::Traces::Configuration.new
            config.index_driver = Trifle::Traces::Driver::Index::Memory.new
            config.data_driver = driver
            config.bump_every = 0
            tracer = Trifle::Traces::Tracer::Hash.new(key: 'jobs/cleanup', config: config, mode: mode)
            tracer.artifact('public.txt', path)
            expect(File.exist?(path)).to be(true)
            tracer.wrapup

            expect(File.exist?(path)).to be(false)
            record = config.index_driver.find(tracer.reference)
            expect(driver.read_artifact(record, name: 'public.txt')).to eq('report')
            driver.delete(record)
          end
        end
      end

      describe 'multi-bucket sharding' do
        let(:driver) { described_class.new(client: client, buckets: buckets) }

        it 'selects names from the configured buckets' do
          names = Array.new(50) { driver.generate_bucket_name }.uniq.sort

          expect(names).to eq(buckets.sort)
        end
      end

      describe '.setup!' do
        it 'writes one lifecycle rule per retention class' do
          described_class.setup!(client: client, buckets: [buckets.first], retentions: [3, 7])

          rules = client.get_bucket_lifecycle_configuration(bucket: buckets.first).rules
          expect(rules.map(&:id)).to contain_exactly('trifle-traces-3d', 'trifle-traces-7d')
          expect(rules.map { |r| r.filter.prefix }).to contain_exactly('3/traces/', '7/traces/')
        end
      end
    end
  else
    it 'is skipped without S3_ENDPOINT' do
      skip 'set S3_ENDPOINT to run S3 data driver specs'
    end
  end
end
