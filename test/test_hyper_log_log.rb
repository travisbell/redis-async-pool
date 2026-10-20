# frozen_string_literal: true

require_relative "helper"
require_relative "lint/hyper_log_log"

class TestHyperLogLogLint < Minitest::Test
  include LintHelper
  include Lint::HyperLogLog
end
