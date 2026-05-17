class ApplicationController < ActionController::Base
  before_action :require_basic_auth

  helper_method :current_week_start_brt, :format_brt, :pending_debt_count

  private

  def require_basic_auth
    authenticate_or_request_with_http_basic("Stay in Law") do |username, password|
      username == ENV.fetch("BASIC_AUTH_USER", "admin") &&
        password == ENV.fetch("BASIC_AUTH_PASSWORD", "changeme")
    end
  end

  def valid_secure_token?(token)
    expected = ENV.fetch("SECURE_TOKEN", "")
    expected.present? && token.to_s == expected
  end

  def current_week_start_brt
    local = TimezoneSupport.brt.utc_to_local(Time.current.utc)
    days_back = (local.wday - 1) % 7
    monday = local - (days_back * 86_400)
    format("%<y>04d-%<m>02d-%<d>02d", y: monday.year, m: monday.month, d: monday.day)
  end

  def pending_debt_count
    OutlawCard.pending.count
  end

  def format_brt(time_or_str)
    TimezoneSupport.format_brt(time_or_str)
  end
end
