class QrCodeGenerator
  class << self
    def call(count:, minutes:)
      count.times.map do
        qr_code = create_unique_qr_code(minutes)
        {token: qr_code.token, minutes: qr_code.minutes}
      end
    end

    private

    def create_unique_qr_code(minutes)
      loop do
        token = SecureRandom.hex(2)
        qr_code = QrCode.new(token: token, minutes: minutes, created_at: Time.current.utc)
        return qr_code if qr_code.save
      rescue ActiveRecord::RecordNotUnique
        next
      end
    end
  end
end
