# frozen_string_literal: true

source "https://rubygems.org"

gemspec

group :development, :test do
  gem "minitest"
  gem "rake"
  gem "rspec", "~> 3.13"
  gem "rubocop-shopify", require: false
end

# The benchmark compares against redis-rb pooled by connection_pool.
group :benchmark do
  gem "connection_pool"
end
