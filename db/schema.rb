def setup_database(db)
  db.create_table?(:qr_tokens) do
    primary_key :id
    String  :token,                unique: true, null: false
    Integer :minutes,                            null: false
    String  :created_at,                         null: false
    String  :last_used_week_start  # 'YYYY-MM-DD' of the Monday (BRT) when last used; NULL if unused
  end

  db.create_table?(:scan_log) do
    primary_key :id
    Integer :qr_token_id, null: false
    String  :scanned_at,  null: false  # ISO-8601 UTC
  end

  db.create_table?(:outlaw_cards) do
    primary_key :id
    String  :description    # optional reason written by admin
    String  :created_at,  null: false  # ISO-8601 UTC
    Integer :redeemed_scan_id          # FK → scan_log.id; NULL = still owed
  end
end
