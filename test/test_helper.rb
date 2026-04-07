# Set RACK_ENV before requiring the app so that:
# - app.rb loads .env.test (taking precedence over .env) via Dotenv.load
# - the DB is created at db/test.db (isolated from development)
ENV['RACK_ENV'] = 'test'

require 'simplecov'
SimpleCov.start

require 'base64'
require 'json'
require 'minitest/autorun'
require 'rack/test'
require_relative '../app'

# Base class for all request tests.
# Each test runs against a fresh set of tables: setup truncates every table
# (in FK-safe order) before each test so tests are fully isolated.
class AppTest < Minitest::Test
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  def setup
    DB[:outlaw_cards].delete
    DB[:scan_log].delete
    DB[:qr_tokens].delete
  end

  private

  # Returns a Rack env hash that satisfies Basic Auth.
  def auth_header
    credentials = Base64.strict_encode64(
      "#{ENV['BASIC_AUTH_USER']}:#{ENV['BASIC_AUTH_PASSWORD']}"
    )
    { 'HTTP_AUTHORIZATION' => "Basic #{credentials}" }
  end
end
