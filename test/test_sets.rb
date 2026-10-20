# frozen_string_literal: true

require_relative "helper"
require_relative "lint/sets"

class TestSetsLint < Minitest::Test
  include LintHelper
  include Lint::Sets
end
