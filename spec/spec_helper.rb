# frozen_string_literal: true

require "redis/async/pool"

Dir[File.join(__dir__, "support/**/*.rb")].each { |file| require file }

RSpec.configure do |config|
  config.example_status_persistence_file_path = ".rspec_status"
  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand(config.seed)

  config.expect_with(:rspec) do |expectations|
    expectations.syntax = :expect
  end

  config.extend(Conformance::DSL)
end
