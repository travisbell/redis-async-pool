# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"
require "rubocop/rake_task"

RSpec::Core::RakeTask.new(:spec)
RuboCop::RakeTask.new



require "rake/testtask"

# redis-rb's own lint tests, against redis-async-pool (see test/helper.rb).
Rake::TestTask.new(:lint) do |task|
  task.libs << "test"
  task.test_files = FileList["test/test_*.rb"]
  task.warning = false
end
task default: [:spec, :lint, :rubocop]
