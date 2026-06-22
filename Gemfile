source "https://rubygems.org"

# ruby File.read(File.join(__dir__, ".ruby-version")).strip

gem "rails", "~> 8.1"
gem "sqlite3", "~> 2.9"
gem "puma", "~> 8.0"
gem "sprockets-rails" # TODO: remove in favor of propshaft?
gem "importmap-rails"
gem "turbo-rails"
gem "stimulus-rails"
gem "thruster", require: false

gem "dotenv"

group :development, :test do
  gem "debug", platforms: %i[mri windows], require: "debug/prelude"
  gem "standardrb", "~> 1.0"
end

group :test do
  gem "simplecov", "~> 0.22", require: false
end
