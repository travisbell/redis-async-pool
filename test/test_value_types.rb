# frozen_string_literal: true

require_relative "helper"
require_relative "lint/value_types"

class TestValueTypesLint < Minitest::Test
  include LintHelper
  include Lint::ValueTypes

  # MOVE requires SELECT to pin to a specific DB, which doesn't work
  # with connection pools — each pool connection has its own DB state.
  def test_move
    skip "MOVE requires connection pinning (not available with pooled connections)"
  end
end
