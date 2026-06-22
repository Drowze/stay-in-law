class OutlawCard < ApplicationRecord
  belongs_to :redeemed_scan, class_name: "Scan", optional: true

  validates :created_at, presence: true

  scope :pending, -> { where(redeemed_scan_id: nil) }
  scope :recent_first, -> { order(created_at: :desc) }
end
