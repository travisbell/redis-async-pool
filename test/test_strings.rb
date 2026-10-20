# frozen_string_literal: true

require_relative "helper"
require_relative "lint/strings"

class TestStringsLint < Minitest::Test
  include LintHelper
  include Lint::Strings
end
