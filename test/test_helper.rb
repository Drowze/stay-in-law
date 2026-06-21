ENV["RAILS_ENV"] ||= "test"

require "simplecov"
SimpleCov.start

require_relative "../config/environment"
require "rails/test_help"
require "base64"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    setup do
      OutlawCard.delete_all
      Scan.delete_all
      QrCode.delete_all
    end

    private

    def auth_headers
      credentials = Base64.strict_encode64(
        "#{ENV.fetch("BASIC_AUTH_USER")}:#{ENV.fetch("BASIC_AUTH_PASSWORD")}"
      )

      {"HTTP_AUTHORIZATION" => "Basic #{credentials}"}
    end

    def current_week_start_brt
      local = Time.current.in_time_zone("Brasilia")
      days_back = (local.wday - 1) % 7
      monday = local - (days_back * 86_400)
      format("%<y>04d-%<m>02d-%<d>02d", y: monday.year, m: monday.month, d: monday.day)
    end
  end
end
