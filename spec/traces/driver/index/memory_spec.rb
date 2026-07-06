# frozen_string_literal: true

RSpec.describe Trifle::Traces::Driver::Index::Memory do
  it_behaves_like 'an index driver' do
    let(:driver) { described_class.new }
  end
end
