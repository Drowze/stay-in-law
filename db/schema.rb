def setup_database(db)
  db.create_table?(:qr_codes) do
    primary_key :id
    String  :token,                unique: true, null: false
    Integer :minutes,                            null: false
    String  :created_at,                         null: false
    String  :last_used_week_start  # 'YYYY-MM-DD' of the Monday (BRT) when last used; NULL if unused
  end

  db.create_table?(:scans) do
    primary_key :id
    Integer :qr_code_id, null: false
    String  :created_at, null: false  # ISO-8601 UTC
  end

  db.create_table?(:outlaw_cards) do
    primary_key :id
    String  :description    # optional reason written by admin
    String  :created_at,  null: false  # ISO-8601 UTC
    Integer :redeemed_scan_id          # FK → scans.id; NULL = still owed
  end
end
