# frozen_string_literal: true

require_relative "helper"
require_relative "lint/sorted_sets"

class TestSortedSetsLint < Minitest::Test
  include LintHelper
  include Lint::SortedSets
end
