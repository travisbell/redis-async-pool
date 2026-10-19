# frozen_string_literal: true

RSpec.describe(Redis::Async::Pool::Compatibility) do
  it "accepts the installed dependencies" do
    expect { described_class.check! }.not_to(raise_error)
  end

  it "names what's missing when a dependency changes" do
    allow(Redis).to(receive(:private_method_defined?).and_call_original)
    allow(Redis).to(receive(:private_method_defined?).with(:initialize_client).and_return(false))

    expect { described_class.check! }.to(raise_error(Redis::Async::Pool::IncompatibleError, /Redis#initialize_client/))
  end

  # Inside Redis::Async, a bare `Async::` resolves to Redis::Async, not the async gem.
  it "refers to the async gem's constants from the top level" do
    lib = File.expand_path("../../../../lib", __dir__)
    offenders = Dir["#{lib}/**/*.rb"].flat_map do |file|
      File.readlines(file).each_with_index.filter_map do |line, index|
        "#{file.delete_prefix("#{lib}/")}:#{index + 1}" if line.sub(/#.*/, "").match?(/(?<![:\w"])Async::/)
      end
    end

    expect(offenders).to(be_empty)
  end
end
