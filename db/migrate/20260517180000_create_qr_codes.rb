class CreateQrCodes < ActiveRecord::Migration[7.2]
  def change
    create_table :qr_codes do |t|
      t.string :token, null: false
      t.integer :minutes, null: false
      t.datetime :created_at, null: false
      t.string :last_used_week_start
    end

    add_index :qr_codes, :token, unique: true
  end
end
