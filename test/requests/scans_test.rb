require_relative '../test_helper'

class ScansRequestTest < AppTest
  # ─── Fixtures ────────────────────────────────────────────────────────────

  def insert_token(minutes: 30, last_used_week_start: nil)
    tok = SecureRandom.hex(2)
    id  = DB[:qr_tokens].insert(
      token:                tok,
      minutes:              minutes,
      created_at:           Time.now.utc.iso8601,
      last_used_week_start: last_used_week_start
    )
    { id: id, token: tok, minutes: minutes }
  end

  def insert_outlaw_card(description: 'test penalty')
    DB[:outlaw_cards].insert(
      description: description,
      created_at:  Time.now.utc.iso8601
    )
  end

  # Forces the countdown to be active by inserting a scan far in the future.
  def activate_countdown(minutes: 9999)
    qr = insert_token(minutes: minutes)
    DB[:scan_log].insert(qr_token_id: qr[:id], scanned_at: Time.now.utc.iso8601)
    qr
  end

  def post_scan(token:)
    post '/scans', { token: token }, auth_header
  end

  def parsed_body
    JSON.parse(last_response.body)
  end

  # Mirrors the app's current_week_start_brt helper.
  def current_week_start_brt
    local     = BRT.utc_to_local(Time.now.utc)
    days_back = (local.wday - 1) % 7
    monday    = local - (days_back * 86400)
    format('%04d-%02d-%02d', monday.year, monday.month, monday.day)
  end

  # ─── 201 — normal scan (no debt) ─────────────────────────────────────────

  def test_returns_201_on_success
    qr = insert_token(minutes: 20)
    post_scan(token: qr[:token])
    assert_equal 201, last_response.status
  end

  def test_response_content_type_is_json
    qr = insert_token
    post_scan(token: qr[:token])
    assert_equal 'application/json', last_response.content_type
  end

  def test_success_body_contains_scan_id
    qr = insert_token
    post_scan(token: qr[:token])
    assert parsed_body['id'].is_a?(Integer)
    assert parsed_body['id'] > 0
  end

  def test_success_body_contains_qr_code
    qr = insert_token(minutes: 15)
    post_scan(token: qr[:token])
    qr_code = parsed_body['qr_code']
    assert_equal qr[:id],      qr_code['id']
    assert_equal qr[:token],   qr_code['token']
    assert_equal qr[:minutes], qr_code['minutes']
  end

  def test_success_body_has_null_outlaw_card_when_no_debt
    qr = insert_token
    post_scan(token: qr[:token])
    assert_nil parsed_body['outlaw_card']
  end

  def test_inserts_row_in_scan_log
    qr = insert_token
    post_scan(token: qr[:token])
    assert_equal 1, DB[:scan_log].count
  end

  def test_scan_log_row_references_correct_token
    qr = insert_token
    post_scan(token: qr[:token])
    assert_equal qr[:id], DB[:scan_log].first[:qr_token_id]
  end

  def test_updates_last_used_week_start_on_token
    qr = insert_token
    post_scan(token: qr[:token])
    updated = DB[:qr_tokens].where(id: qr[:id]).first
    refute_nil updated[:last_used_week_start]
  end

  # ─── 201 — debt-payment scan ─────────────────────────────────────────────

  def test_returns_201_when_paying_debt
    insert_outlaw_card
    qr = insert_token
    post_scan(token: qr[:token])
    assert_equal 201, last_response.status
  end

  def test_success_body_contains_outlaw_card_when_debt_exists
    insert_outlaw_card(description: 'stayed up late')
    qr = insert_token
    post_scan(token: qr[:token])
    oc = parsed_body['outlaw_card']
    refute_nil oc
    assert oc['id'].is_a?(Integer)
    assert_equal 'stayed up late', oc['description']
  end

  def test_redeems_oldest_outlaw_card
    card1_id = insert_outlaw_card(description: 'first')
    insert_outlaw_card(description: 'second')
    qr = insert_token
    post_scan(token: qr[:token])
    # oldest card should be redeemed
    card1 = DB[:outlaw_cards].where(id: card1_id).first
    refute_nil card1[:redeemed_scan_id]
    # newer card should still be pending
    pending = DB[:outlaw_cards].where(redeemed_scan_id: nil).count
    assert_equal 1, pending
  end

  def test_debt_scan_still_inserts_scan_log_row
    insert_outlaw_card
    qr = insert_token
    post_scan(token: qr[:token])
    assert_equal 1, DB[:scan_log].count
  end

  def test_debt_scan_still_updates_week_start
    insert_outlaw_card
    qr = insert_token
    post_scan(token: qr[:token])
    updated = DB[:qr_tokens].where(id: qr[:id]).first
    refute_nil updated[:last_used_week_start]
  end

  def test_redeemed_scan_id_matches_inserted_scan
    insert_outlaw_card
    qr = insert_token
    post_scan(token: qr[:token])
    scan_id   = DB[:scan_log].first[:id]
    card      = DB[:outlaw_cards].first
    assert_equal scan_id, card[:redeemed_scan_id]
  end

  # ─── 422 — token valid but already used this week ────────────────────────

  def test_returns_422_when_token_already_used_this_week
    week_start = current_week_start_brt
    qr = insert_token(last_used_week_start: week_start)
    post_scan(token: qr[:token])
    assert_equal 422, last_response.status
  end

  def test_already_used_error_has_code_token_already_used
    week_start = current_week_start_brt
    qr = insert_token(last_used_week_start: week_start)
    post_scan(token: qr[:token])
    assert_equal 'token_already_used', parsed_body['code']
  end

  def test_already_used_does_not_insert_scan_log_row
    week_start = current_week_start_brt
    qr = insert_token(last_used_week_start: week_start)
    post_scan(token: qr[:token])
    assert_equal 0, DB[:scan_log].count
  end

  # ─── 422 — countdown still active ────────────────────────────────────────

  def test_returns_422_when_countdown_is_active
    activate_countdown
    qr = insert_token
    post_scan(token: qr[:token])
    assert_equal 422, last_response.status
  end

  def test_countdown_active_error_has_code_countdown_active
    activate_countdown
    qr = insert_token
    post_scan(token: qr[:token])
    assert_equal 'countdown_active', parsed_body['code']
  end

  def test_countdown_active_does_not_insert_extra_scan_log_row
    activate_countdown   # creates 1 scan
    qr = insert_token
    post_scan(token: qr[:token])
    assert_equal 1, DB[:scan_log].count
  end

  # ─── 403 — invalid / missing token ───────────────────────────────────────

  def test_returns_403_for_unknown_token
    post_scan(token: 'zzzz')
    assert_equal 403, last_response.status
  end

  def test_returns_403_for_empty_token
    post_scan(token: '')
    assert_equal 403, last_response.status
  end

  def test_invalid_token_does_not_insert_scan_log_row
    post_scan(token: 'zzzz')
    assert_equal 0, DB[:scan_log].count
  end

  # ─── 401 — no basic auth ─────────────────────────────────────────────────

  def test_returns_401_without_basic_auth
    qr = insert_token
    post '/scans', token: qr[:token]
    assert_equal 401, last_response.status
  end
end
