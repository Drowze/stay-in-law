class QrCode < ApplicationRecord
  has_many :scans, dependent: :restrict_with_exception

  validates :token, presence: true, uniqueness: true, format: {with: /\A[0-9a-f]{4}\z/}
  validates :minutes, presence: true, inclusion: {in: 1..60}
  validates :created_at, presence: true

  def used_in_week?(week_start)
    last_used_week_start == week_start
  end

  def mark_used_this_week!(week_start)
    update!(last_used_week_start: week_start)
  end
end
