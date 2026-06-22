class ScansController < ApplicationController
  def create
    result = ScanProcessor.new(token: params[:token], current_week_start: current_week_start_brt).call
    render json: result.body, status: result.status
  end
end
