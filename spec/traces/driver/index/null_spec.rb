# frozen_string_literal: true

RSpec.describe Trifle::Traces::Driver::Index::Null do
  subject(:driver) { described_class.new }

  it 'generates references without persisting anything' do
    record = Trifle::Traces::TraceRecord.new(reference: driver.generate_reference, key: 'a/b')

    expect(driver.create(record)).to eq(record.reference)
    expect(driver.find(record.reference)).to be_nil
    expect(driver.search[:traces]).to eq([])
  end

  it 'declares capabilities' do
    expect(driver.capabilities[:update]).to be true
    expect(driver.capabilities[:search]).to be false
  end
end
