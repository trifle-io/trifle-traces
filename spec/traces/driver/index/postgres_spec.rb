# frozen_string_literal: true

RSpec.describe Trifle::Traces::Driver::Index::Postgres do
  postgres_url = ENV['POSTGRES_URL']

  if postgres_url
    require 'pg'

    let(:client) { PG.connect(postgres_url) }
    let(:table_name) { 'trifle_traces_postgres_spec' }

    before(:each) do
      client.exec("DROP TABLE IF EXISTS #{table_name}")
      described_class.setup!(client, table_name: table_name)
    end

    after(:each) do
      client.exec("DROP TABLE IF EXISTS #{table_name}")
      client.close
    end

    it_behaves_like 'an index driver' do
      let(:driver) { described_class.new(client, table_name: table_name) }
    end

    describe '.setup!' do
      it 'creates the table and search indexes' do
        indexes = client.exec_params(
          'SELECT indexname FROM pg_indexes WHERE tablename = $1',
          [table_name]
        ).map { |row| row['indexname'] }

        expect(indexes).to include(
          "#{table_name}_segments_gin",
          "#{table_name}_tags_gin",
          "#{table_name}_state_started",
          "#{table_name}_started",
          "#{table_name}_duration_started",
          "#{table_name}_expires_at"
        )
      end
    end

    describe '.cleanup!' do
      it 'deletes expired records only' do
        driver = described_class.new(client, table_name: table_name)
        now = Time.now
        expired = cleanup_record(driver, 'expired', now - 60)
        current = cleanup_record(driver, 'current', now + 60)
        driver.create(expired)
        driver.create(current)

        expect(driver.cleanup!(before: now)).to eq(1)
        expect(driver.find(expired.reference)).to be_nil
        expect(driver.find(current.reference)).not_to be_nil
      end
    end

    def cleanup_record(driver, key, expires_at)
      now = Time.now
      Trifle::Traces::TraceRecord.new(
        reference: driver.generate_reference,
        key: "jobs/#{key}", state: :success, tags: [], meta: nil, context: {},
        duration: 1, counters: Trifle::Traces::TraceRecord.empty_counters,
        length: 1, parts: 1, first_at: now, last_at: now,
        retention: 3, expires_at: expires_at, bucket_id: 0
      )
    end
  else
    it 'is skipped without POSTGRES_URL' do
      skip 'set POSTGRES_URL to run PostgreSQL index driver specs'
    end
  end

  it 'rejects unsafe table names' do
    expect { described_class.new(Object.new, table_name: 'traces; DROP TABLE users') }
      .to raise_error(ArgumentError, /invalid PostgreSQL table name/)
  end
end
