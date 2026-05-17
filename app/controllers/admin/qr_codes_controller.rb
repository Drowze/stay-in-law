module Admin
  class QrCodesController < ApplicationController
    def new
    end

    def create
      unless valid_secure_token?(params[:secure_token])
        render json: {error: "Token de segurança inválido."}, status: :forbidden
        return
      end

      count = params[:count].to_i
      minutes = params[:minutes].to_i

      unless (1..50).cover?(count)
        render json: {error: "A quantidade deve estar entre 1 e 50."}, status: :unprocessable_entity
        return
      end

      unless (1..60).cover?(minutes)
        render json: {error: "Os minutos devem estar entre 1 e 60."}, status: :unprocessable_entity
        return
      end

      render json: QrCodeGenerator.call(count: count, minutes: minutes)
    end
  end
end
