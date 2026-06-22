class Scan < ApplicationRecord
  belongs_to :qr_code
  has_one :redeemed_outlaw_card, class_name: "OutlawCard", foreign_key: :redeemed_scan_id, dependent: :nullify

  validates :created_at, presence: true

  scope :recent_with_details, lambda {
    includes(:qr_code, :redeemed_outlaw_card)
      .left_joins(:redeemed_outlaw_card)
      .order(created_at: :desc)
  }

  scope :countdown_candidates, lambda {
    left_joins(:redeemed_outlaw_card)
      .where(outlaw_cards: {id: nil})
      .includes(:qr_code)
      .order(created_at: :desc)
  }
end
