module Admin
  class OutlawCardsController < ApplicationController
    def index
      @pending_debt = pending_debt_count
      @recent_cards = OutlawCard.recent_first.limit(10)
      @success = params[:success] == "1"
    end

    def create
      unless valid_secure_token?(params[:secure_token])
        @message = "Token de segurança inválido."
        render "shared/error", status: :forbidden
        return
      end

      description = params[:description].to_s.strip
      description = nil if description.blank?

      OutlawCard.create!(description: description, created_at: Time.current.utc)
      redirect_to admin_outlaw_cards_path(success: 1)
    end
  end
end
