class ScanProcessor
  Result = Struct.new(:status, :body, keyword_init: true)

  def initialize(token:, current_week_start:)
    @token = token.to_s.strip
    @current_week_start = current_week_start
  end

  def call
    return invalid_qr_result if @token.blank?

    qr = QrCode.find_by(token: @token)
    return invalid_qr_result unless qr

    if qr.used_in_week?(@current_week_start)
      return Result.new(
        status: :unprocessable_entity,
        body: {error: "Este QR code já foi usado esta semana. Tente outro!", code: "token_already_used"}
      )
    end

    countdown_end_at = CountdownService.end_at
    if countdown_end_at&.future? && OutlawCard.pending.none?
      return Result.new(
        status: :unprocessable_entity,
        body: {
          error: "A contagem regressiva ainda está ativa. Aguarde terminar antes de escanear um novo QR code.",
          code: "countdown_active"
        }
      )
    end

    scan = nil
    redeemed_card = nil

    ActiveRecord::Base.transaction do
      scan = Scan.create!(qr_code: qr, created_at: Time.current.utc)
      qr.mark_used_this_week!(@current_week_start)

      oldest_debt = OutlawCard.pending.order(:created_at).first
      if oldest_debt
        oldest_debt.update!(redeemed_scan: scan)
        redeemed_card = {id: oldest_debt.id, description: oldest_debt.description}
      end
    end

    Result.new(
      status: :created,
      body: {
        id: scan.id,
        qr_code: {id: qr.id, token: qr.token, minutes: qr.minutes},
        outlaw_card: redeemed_card
      }
    )
  end

  private

  def invalid_qr_result
    Result.new(status: :forbidden, body: {error: "QR code inválido."})
  end
end
