require "test_helper"

class ScansRequestTest < ActionDispatch::IntegrationTest
  def insert_token(minutes: 30, last_used_week_start: nil)
    qr = QrCode.create!(
      token: SecureRandom.hex(2),
      minutes: minutes,
      created_at: Time.current.utc,
      last_used_week_start: last_used_week_start
    )
    {id: qr.id, token: qr.token, minutes: qr.minutes}
  end

  def insert_outlaw_card(description: "test penalty")
    OutlawCard.create!(description: description, created_at: Time.current.utc)
  end

  def activate_countdown(minutes: 60)
    qr = insert_token(minutes: minutes)
    Scan.create!(qr_code_id: qr[:id], created_at: Time.current.utc)
    qr
  end

  def post_scan(token:)
    post scans_path, params: {token: token}, headers: auth_headers
  end

  def test_returns_201_on_success
    qr = insert_token(minutes: 20)
    post_scan(token: qr[:token])
    assert_response :created
  end

  def test_response_content_type_is_json
    qr = insert_token
    post_scan(token: qr[:token])
    assert_equal "application/json; charset=utf-8", response.content_type
  end

  def test_success_body_contains_scan_id
    qr = insert_token
    post_scan(token: qr[:token])
    assert response.parsed_body["id"].is_a?(Integer)
    assert response.parsed_body["id"].positive?
  end

  def test_success_body_contains_qr_code
    qr = insert_token(minutes: 15)
    post_scan(token: qr[:token])
    qr_code = response.parsed_body["qr_code"]
    assert_equal qr[:id], qr_code["id"]
    assert_equal qr[:token], qr_code["token"]
    assert_equal qr[:minutes], qr_code["minutes"]
  end

  def test_success_body_has_null_outlaw_card_when_no_debt
    qr = insert_token
    post_scan(token: qr[:token])
    assert_nil response.parsed_body["outlaw_card"]
  end

  def test_inserts_row_in_scans
    qr = insert_token
    post_scan(token: qr[:token])
    assert_equal 1, Scan.count
  end

  def test_scans_row_references_correct_qr_code
    qr = insert_token
    post_scan(token: qr[:token])
    assert_equal qr[:id], Scan.first.qr_code_id
  end

  def test_updates_last_used_week_start_on_qr_code
    qr = insert_token
    post_scan(token: qr[:token])
    refute_nil QrCode.find(qr[:id]).last_used_week_start
  end

  def test_returns_201_when_paying_debt
    insert_outlaw_card
    qr = insert_token
    post_scan(token: qr[:token])
    assert_response :created
  end

  def test_success_body_contains_outlaw_card_when_debt_exists
    insert_outlaw_card(description: "stayed up late")
    qr = insert_token
    post_scan(token: qr[:token])
    oc = response.parsed_body["outlaw_card"]
    refute_nil oc
    assert oc["id"].is_a?(Integer)
    assert_equal "stayed up late", oc["description"]
  end

  def test_redeems_oldest_outlaw_card
    card1 = insert_outlaw_card(description: "first")
    insert_outlaw_card(description: "second")
    qr = insert_token
    post_scan(token: qr[:token])
    refute_nil card1.reload.redeemed_scan_id
    assert_equal 1, OutlawCard.pending.count
  end

  def test_debt_scan_still_inserts_scans_row
    insert_outlaw_card
    qr = insert_token
    post_scan(token: qr[:token])
    assert_equal 1, Scan.count
  end

  def test_debt_scan_still_updates_week_start
    insert_outlaw_card
    qr = insert_token
    post_scan(token: qr[:token])
    refute_nil QrCode.find(qr[:id]).last_used_week_start
  end

  def test_redeemed_scan_id_matches_inserted_scan
    insert_outlaw_card
    qr = insert_token
    post_scan(token: qr[:token])
    assert_equal Scan.first.id, OutlawCard.first.redeemed_scan_id
  end

  def test_returns_422_when_token_already_used_this_week
    qr = insert_token(last_used_week_start: current_week_start_brt)
    post_scan(token: qr[:token])
    assert_response :unprocessable_entity
  end

  def test_already_used_error_has_code_token_already_used
    qr = insert_token(last_used_week_start: current_week_start_brt)
    post_scan(token: qr[:token])
    assert_equal "token_already_used", response.parsed_body["code"]
  end

  def test_already_used_does_not_insert_scans_row
    qr = insert_token(last_used_week_start: current_week_start_brt)
    post_scan(token: qr[:token])
    assert_equal 0, Scan.count
  end

  def test_returns_422_when_countdown_is_active_and_no_debt
    activate_countdown
    qr = insert_token
    post_scan(token: qr[:token])
    assert_response :unprocessable_entity
  end

  def test_countdown_active_error_has_code_countdown_active
    activate_countdown
    qr = insert_token
    post_scan(token: qr[:token])
    assert_equal "countdown_active", response.parsed_body["code"]
  end

  def test_countdown_active_does_not_insert_extra_scans_row
    activate_countdown
    qr = insert_token
    post_scan(token: qr[:token])
    assert_equal 1, Scan.count
  end

  def test_returns_201_when_countdown_active_but_debt_exists
    activate_countdown
    insert_outlaw_card
    qr = insert_token
    post_scan(token: qr[:token])
    assert_response :created
  end

  def test_debt_scan_during_countdown_redeems_outlaw_card
    activate_countdown
    insert_outlaw_card(description: "active debt")
    qr = insert_token
    post_scan(token: qr[:token])
    refute_nil response.parsed_body["outlaw_card"]
    assert_equal 0, OutlawCard.pending.count
  end

  def test_debt_scan_during_countdown_inserts_scans_row
    activate_countdown
    insert_outlaw_card
    qr = insert_token
    post_scan(token: qr[:token])
    assert_equal 2, Scan.count
  end

  def test_returns_403_for_unknown_token
    post_scan(token: "zzzz")
    assert_response :forbidden
  end

  def test_returns_403_for_empty_token
    post_scan(token: "")
    assert_response :forbidden
  end

  def test_invalid_token_does_not_insert_scans_row
    post_scan(token: "zzzz")
    assert_equal 0, Scan.count
  end

  def test_returns_401_without_basic_auth
    qr = insert_token
    post scans_path, params: {token: qr[:token]}
    assert_response :unauthorized
  end
end
