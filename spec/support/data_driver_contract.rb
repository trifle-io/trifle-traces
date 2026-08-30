# frozen_string_literal: true

# Shared contract every data driver must satisfy. Include with:
#   it_behaves_like 'a data driver' do
#     let(:driver) { ... }
#   end
RSpec.shared_examples 'a data driver' do
  let(:record) do
    Trifle::Traces::TraceRecord.new(
      reference: Trifle::Traces::Ref.generate, key: 'jobs/import/products',
      state: :running, tags: [], meta: nil, context: {},
      duration: 0, counters: Trifle::Traces::TraceRecord.empty_counters,
      length: 0, parts: 0, first_at: Time.now, last_at: Time.now,
      retention: 3, expires_at: Time.now + (3 * 86_400),
      bucket_id: driver.generate_bucket_id
    )
  end

  let(:entries) do
    [
      { at: 1_700_000_000, message: 'Tracer has been initialized', state: :success, type: :text, level: 0 },
      { at: 1_700_000_001, message: 'Doing work', state: :error, type: :head, level: 1 }
    ]
  end

  describe '#write_part and #read_part' do
    it 'round-trips entries with symbol states and types' do
      driver.write_part(record, part: 1, entries: entries)

      read = driver.read_part(record, part: 1)
      expect(read.count).to eq(2)
      expect(read.first[:message]).to eq('Tracer has been initialized')
      expect(read.first[:state]).to eq(:success)
      expect(read.first[:type]).to eq(:text)
      expect(read.last[:level]).to eq(1)
    end
  end

  describe '#read' do
    it 'concatenates all parts in order' do
      driver.write_part(record, part: 1, entries: [entries.first])
      driver.write_part(record, part: 2, entries: [entries.last])
      record.parts = 2

      read = driver.read(record)
      expect(read.map { |e| e[:message] }).to eq(['Tracer has been initialized', 'Doing work'])
    end
  end

  describe '#write_artifact and #read_artifact' do
    it 'stores inline payloads' do
      driver.write_artifact(record, name: 'oversized.txt', payload: 'x' * 1000)

      expect(driver.read_artifact(record, name: 'oversized.txt')).to eq('x' * 1000)
    end

    it 'stores files from disk' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'report.csv')
        File.write(path, "a,b\n1,2\n")
        driver.write_artifact(record, name: 'report.csv', path: path)

        expect(driver.read_artifact(record, name: 'report.csv')).to eq("a,b\n1,2\n")
      end
    end
  end

  describe '#delete' do
    it 'purges parts and artifacts' do
      driver.write_part(record, part: 1, entries: entries)
      driver.write_artifact(record, name: 'a.txt', payload: 'a')
      record.parts = 1

      driver.delete(record)

      expect { driver.read_part(record, part: 1) }.to raise_error(StandardError)
    end
  end
end
