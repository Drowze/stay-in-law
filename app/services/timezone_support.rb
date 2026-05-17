class TimezoneSupport
  class << self
    def brt
      @brt ||= TZInfo::Timezone.get("America/Sao_Paulo")
    end

    def utc_to_brt(time_or_str)
      return nil if time_or_str.blank?

      utc_time = time_or_str.is_a?(Time) ? time_or_str.utc : Time.parse(time_or_str.to_s).utc
      brt.utc_to_local(utc_time)
    end

    def format_brt(time_or_str)
      local = utc_to_brt(time_or_str)
      return "—" unless local

      local.strftime("%d/%m %H:%M")
    end
  end
end
