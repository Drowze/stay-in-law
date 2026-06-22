# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.2].define(version: 2026_05_17_180020) do
  create_table "outlaw_cards", force: :cascade do |t|
    t.text "description"
    t.datetime "created_at", null: false
    t.integer "redeemed_scan_id"
    t.index ["redeemed_scan_id"], name: "index_outlaw_cards_on_redeemed_scan_id"
  end

  create_table "qr_codes", force: :cascade do |t|
    t.string "token", null: false
    t.integer "minutes", null: false
    t.datetime "created_at", null: false
    t.string "last_used_week_start"
    t.index ["token"], name: "index_qr_codes_on_token", unique: true
  end

  create_table "scans", force: :cascade do |t|
    t.integer "qr_code_id", null: false
    t.datetime "created_at", null: false
    t.index ["qr_code_id"], name: "index_scans_on_qr_code_id"
  end

  add_foreign_key "outlaw_cards", "scans", column: "redeemed_scan_id"
  add_foreign_key "scans", "qr_codes"
end
