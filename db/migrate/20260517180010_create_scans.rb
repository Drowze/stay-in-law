class CreateScans < ActiveRecord::Migration[7.2]
  def change
    create_table :scans do |t|
      t.references :qr_code, null: false, foreign_key: true
      t.datetime :created_at, null: false
    end
  end
end
