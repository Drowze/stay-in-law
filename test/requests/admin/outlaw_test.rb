require "test_helper"

class AdminOutlawCardsTest < ActionDispatch::IntegrationTest
  def insert_outlaw_card(description: "test", redeemed: false)
    card = OutlawCard.create!(description: description, created_at: Time.current.utc)

    return card unless redeemed

    qr = QrCode.create!(token: SecureRandom.hex(2), minutes: 10, created_at: Time.current.utc)
    scan = Scan.create!(qr_code: qr, created_at: Time.current.utc)
    card.update!(redeemed_scan: scan)
    card
  end

  def post_outlaw(params = {})
    defaults = {secure_token: ENV.fetch("SECURE_TOKEN"), description: "bad behaviour"}
    post admin_outlaw_cards_path, params: defaults.merge(params), headers: auth_headers
  end

  def test_get_requires_basic_auth
    get admin_outlaw_cards_path
    assert_response :unauthorized
  end

  def test_get_returns_200_with_auth
    get admin_outlaw_cards_path, headers: auth_headers
    assert_response :success
  end

  def test_get_shows_pending_debt_count
    2.times { insert_outlaw_card }
    get admin_outlaw_cards_path, headers: auth_headers
    assert_includes response.body, "2"
  end

  def test_get_shows_recent_cards
    insert_outlaw_card(description: "stayed up late")
    get admin_outlaw_cards_path, headers: auth_headers
    assert_includes response.body, "stayed up late"
  end

  def test_get_shows_success_notice_when_param_present
    get admin_outlaw_cards_path, params: {success: "1"}, headers: auth_headers
    assert_includes response.body, "sucesso"
  end

  def test_get_does_not_show_success_notice_by_default
    get admin_outlaw_cards_path, headers: auth_headers
    refute_includes response.body, "sucesso"
  end

  def test_get_shows_redeemed_and_pending_cards
    insert_outlaw_card(description: "pending one")
    insert_outlaw_card(description: "paid one", redeemed: true)
    get admin_outlaw_cards_path, headers: auth_headers
    assert_includes response.body, "pending one"
    assert_includes response.body, "paid one"
  end

  def test_post_requires_basic_auth
    post admin_outlaw_cards_path, params: {secure_token: ENV.fetch("SECURE_TOKEN")}
    assert_response :unauthorized
  end

  def test_post_returns_403_with_wrong_secure_token
    post_outlaw(secure_token: "wrong")
    assert_response :forbidden
  end

  def test_post_returns_403_with_missing_secure_token
    post_outlaw(secure_token: "")
    assert_response :forbidden
  end

  def test_post_does_not_create_card_with_wrong_token
    post_outlaw(secure_token: "wrong")
    assert_equal 0, OutlawCard.count
  end

  def test_post_creates_outlaw_card
    post_outlaw(description: "test penalty")
    assert_equal 1, OutlawCard.count
  end

  def test_post_stores_correct_description
    post_outlaw(description: "skipped homework")
    assert_equal "skipped homework", OutlawCard.first.description
  end

  def test_post_stores_nil_description_when_blank
    post_outlaw(description: "   ")
    assert_nil OutlawCard.first.description
  end

  def test_post_stores_nil_description_when_omitted
    post_outlaw(description: "")
    assert_nil OutlawCard.first.description
  end

  def test_post_redirects_to_outlaw_cards_success_page
    post_outlaw
    assert_response :redirect
    assert_includes response.headers["Location"], "/admin/outlaw_cards?success=1"
  end

  def test_post_new_card_has_null_redeemed_scan_id
    post_outlaw
    assert_nil OutlawCard.first.redeemed_scan_id
  end

  def test_post_stores_created_at_timestamp
    post_outlaw
    assert_match(/\d{4}-\d{2}-\d{2}/, OutlawCard.first.created_at.to_s)
  end
end
