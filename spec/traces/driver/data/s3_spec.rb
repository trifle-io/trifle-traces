# frozen_string_literal: true

RSpec.describe Trifle::Traces::Driver::Data::S3 do
  endpoint = ENV['S3_ENDPOINT']

  if endpoint
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

    describe 'multi-bucket sharding' do
      let(:driver) { described_class.new(client: client, buckets: buckets) }

      it 'spreads bucket ids across the configured buckets' do
        ids = Array.new(50) { driver.generate_bucket_id }.uniq.sort

        expect(ids).to eq([0, 1])
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
  else
    it 'is skipped without S3_ENDPOINT' do
      skip 'set S3_ENDPOINT to run S3 data driver specs'
    end
  end
end
