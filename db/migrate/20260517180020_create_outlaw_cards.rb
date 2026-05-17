class CreateOutlawCards < ActiveRecord::Migration[7.2]
  def change
    create_table :outlaw_cards do |t|
      t.text :description
      t.datetime :created_at, null: false
      t.references :redeemed_scan, foreign_key: {to_table: :scans}
    end
  end
end
