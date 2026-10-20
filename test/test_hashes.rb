# frozen_string_literal: true

require_relative "helper"
require_relative "lint/hashes"

class TestHashesLint < Minitest::Test
  include LintHelper
  include Lint::Hashes
end
