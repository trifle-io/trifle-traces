# frozen_string_literal: true

RSpec.describe Trifle::Traces::Driver::Index::Mongo do
  mongo_url = ENV['MONGO_URL']

  if mongo_url
    require 'mongo'

    let(:client) { Mongo::Client.new(mongo_url) }
    let(:collection_name) { 'trifle_traces_spec' }

    before(:each) do
      client[collection_name].drop
      described_class.setup!(client, collection_name: collection_name)
    end

    after(:each) do
      client[collection_name].drop
      client.close
    end

    it_behaves_like 'an index driver' do
      let(:driver) { described_class.new(client, collection_name: collection_name) }
    end

    describe '.setup!' do
      it 'creates the search and TTL indexes' do
        keys = client[collection_name].indexes.map { |index| index['key'].to_h }

        expect(keys).to include('segments' => 1, 'first_at' => -1, '_id' => -1)
        expect(keys).to include('tags' => 1, 'first_at' => -1, '_id' => -1)
        expect(keys).to include('state' => 1, 'first_at' => -1, '_id' => -1)
        expect(keys).to include('first_at' => -1, '_id' => -1)
        expect(keys).to include('duration' => 1, 'first_at' => -1, '_id' => -1)
        expect(keys).to include('expires_at' => 1)
      end
    end
  else
    it 'is skipped without MONGO_URL' do
      skip 'set MONGO_URL to run Mongo index driver specs'
    end
  end
end
