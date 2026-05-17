class CountdownService
  class << self
    def end_at
      scan = Scan.countdown_candidates.first
      return nil unless scan

      scan.created_at + scan.qr_code.minutes.minutes
    end
  end
end
