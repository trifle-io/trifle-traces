# frozen_string_literal: true

RSpec.describe Trifle::Traces::Ref do
  it 'generates 26-character Crockford base32 references' do
    reference = described_class.generate

    expect(reference).to match(/\A[0-9A-HJKMNP-TV-Z]{26}\z/)
  end

  it 'generates unique references' do
    references = Array.new(1000) { described_class.generate }

    expect(references.uniq.count).to eq(1000)
  end

  it 'sorts lexicographically by time' do
    older = described_class.generate(at: Time.now - 60)
    newer = described_class.generate(at: Time.now)

    expect(older).to be < newer
  end
end
