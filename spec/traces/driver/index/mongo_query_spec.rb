# frozen_string_literal: true

require 'bson'

RSpec.describe Trifle::Traces::Driver::Index::Mongo do
  describe '#search query construction' do
    let(:client) { double('client') }
    let(:collection) { double('collection') }
    let(:view) { double('view', to_a: []) }
    let(:driver) { described_class.new(client) }
    let(:from) { Time.utc(2026, 10, 6) }
    let(:to) { Time.utc(2026, 10, 7) }
    let(:at) { Time.utc(2026, 10, 6, 12, 30, 0, 123_000) }
    let(:reference) { '68e3bfc80000000000000002' }
    let(:cursor) do
      Trifle::Traces::Driver::Index::Query.encode_cursor(
        Trifle::Traces::TraceRecord.new(key: 'jobs/App.Worker', reference: reference, first_at: at)
      )
    end

    before do
      allow(client).to receive(:[]).with('trifle_traces').and_return(collection)
      allow(collection).to receive(:find).and_return(view)
      allow(view).to receive(:sort).and_return(view)
      allow(view).to receive(:limit).and_return(view)
    end

    it 'encodes sort fields in chronological index order' do
      expect(view).to receive(:sort) do |sort|
        encoded = BSON::Document.new(sort).to_bson.to_s
        expect(encoded.index("first_at\0")).to be < encoded.index("_id\0")
        view
      end
      expect(view).to receive(:limit).with(20).and_return(view)

      driver.search
    end

    it 'preserves the inclusive start and exclusive end on the first page' do
      expect(collection).to receive(:find).with({ first_at: { '$gte' => from, '$lt' => to } }).and_return(view)

      expect(driver.search(from: from, to: to)).to eq(traces: [], cursor: nil)
    end

    it 'bounds the next page at the cursor while preserving its time range and tie breaker' do
      expect(collection).to receive(:find).with({
        first_at: { '$gte' => from, '$lt' => to, '$lte' => at },
        '$or' => [
          { first_at: { '$lt' => at } },
          { first_at: at, _id: { '$lt' => BSON::ObjectId.from_string(reference) } }
        ]
      }).and_return(view)

      driver.search(from: from, to: to, cursor: cursor)
    end

    it 'bounds the index scan without an explicit time range' do
      driver.search(cursor: cursor)

      expect(collection).to have_received(:find).with(hash_including(first_at: { '$lte' => at }))
    end

    it 'preserves an exclusive time bound earlier than the cursor' do
      before_cursor = Time.utc(2026, 10, 6, 10)
      driver.search(to: before_cursor, cursor: cursor)

      expect(collection).to have_received(:find).with(
        hash_including(first_at: { '$lt' => before_cursor, '$lte' => at })
      )
    end
  end
end
