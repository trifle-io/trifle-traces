# frozen_string_literal: true

RSpec.describe Trifle::Traces::Driver::Data::Memory do
  it_behaves_like 'a data driver' do
    let(:driver) { described_class.new }
  end
end
