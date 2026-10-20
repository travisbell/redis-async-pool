# frozen_string_literal: true

require_relative "helper"
require_relative "lint/lists"

class TestListsLint < Minitest::Test
  include LintHelper
  include Lint::Lists
end
