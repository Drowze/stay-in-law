class HomeController < ApplicationController
  def index
    @countdown_end_at = CountdownService.end_at
    @countdown_active = @countdown_end_at.present? && @countdown_end_at > Time.current.utc
    @pending_debt = pending_debt_count
    @notice = params[:notice]

    @recent_scans = Scan.recent_with_details.limit(5)
  end
end
