require_relative "../../test_helper"

class AdminOutlawCardsTest < AppTest
  # ─── Helpers ──────────────────────────────────────────────────────────────

  def insert_outlaw_card(description: "test", redeemed: false)
    id = DB[:outlaw_cards].insert(
      description: description,
      created_at: Time.now.utc.iso8601
    )
    if redeemed
      qr_id = DB[:qr_codes].insert(token: SecureRandom.hex(2), minutes: 10, created_at: Time.now.utc.iso8601)
      scan_id = DB[:scans].insert(qr_code_id: qr_id, created_at: Time.now.utc.iso8601)
      DB[:outlaw_cards].where(id: id).update(redeemed_scan_id: scan_id)
    end
    id
  end

  def post_outlaw(params = {})
    defaults = {secure_token: ENV["SECURE_TOKEN"], description: "bad behaviour"}
    post "/admin/outlaw_cards", defaults.merge(params), auth_header
  end

  # ─── GET /admin/outlaw_cards — auth ──────────────────────────────────────

  def test_get_requires_basic_auth
    get "/admin/outlaw_cards"
    assert_equal 401, last_response.status
  end

  def test_get_returns_200_with_auth
    get "/admin/outlaw_cards", {}, auth_header
    assert_equal 200, last_response.status
  end

  # ─── GET /admin/outlaw_cards — content ───────────────────────────────────

  def test_get_shows_pending_debt_count
    2.times { insert_outlaw_card }
    get "/admin/outlaw_cards", {}, auth_header
    assert_includes last_response.body, "2"
  end

  def test_get_shows_recent_cards
    insert_outlaw_card(description: "stayed up late")
    get "/admin/outlaw_cards", {}, auth_header
    assert_includes last_response.body, "stayed up late"
  end

  def test_get_shows_success_notice_when_param_present
    get "/admin/outlaw_cards", {success: "1"}, auth_header
    assert_includes last_response.body, "sucesso"
  end

  def test_get_does_not_show_success_notice_by_default
    get "/admin/outlaw_cards", {}, auth_header
    refute_includes last_response.body, "sucesso"
  end

  def test_get_shows_redeemed_and_pending_cards
    insert_outlaw_card(description: "pending one")
    insert_outlaw_card(description: "paid one", redeemed: true)
    get "/admin/outlaw_cards", {}, auth_header
    assert_includes last_response.body, "pending one"
    assert_includes last_response.body, "paid one"
  end

  # ─── POST /admin/outlaw_cards — auth ─────────────────────────────────────

  def test_post_requires_basic_auth
    post "/admin/outlaw_cards", {secure_token: ENV["SECURE_TOKEN"]}
    assert_equal 401, last_response.status
  end

  # ─── POST /admin/outlaw_cards — secure token validation ──────────────────

  def test_post_returns_403_with_wrong_secure_token
    post_outlaw(secure_token: "wrong")
    assert_equal 403, last_response.status
  end

  def test_post_returns_403_with_missing_secure_token
    post_outlaw(secure_token: "")
    assert_equal 403, last_response.status
  end

  def test_post_does_not_create_card_with_wrong_token
    post_outlaw(secure_token: "wrong")
    assert_equal 0, DB[:outlaw_cards].count
  end

  # ─── POST /admin/outlaw_cards — success ──────────────────────────────────

  def test_post_creates_outlaw_card
    post_outlaw(description: "test penalty")
    assert_equal 1, DB[:outlaw_cards].count
  end

  def test_post_stores_correct_description
    post_outlaw(description: "skipped homework")
    card = DB[:outlaw_cards].first
    assert_equal "skipped homework", card[:description]
  end

  def test_post_stores_nil_description_when_blank
    post_outlaw(description: "   ")
    card = DB[:outlaw_cards].first
    assert_nil card[:description]
  end

  def test_post_stores_nil_description_when_omitted
    post_outlaw(description: "")
    card = DB[:outlaw_cards].first
    assert_nil card[:description]
  end

  def test_post_redirects_to_outlaw_cards_success_page
    post_outlaw
    assert_equal 302, last_response.status
    assert_includes last_response.headers["Location"], "/admin/outlaw_cards?success=1"
  end

  def test_post_new_card_has_null_redeemed_scan_id
    post_outlaw
    card = DB[:outlaw_cards].first
    assert_nil card[:redeemed_scan_id]
  end

  def test_post_stores_created_at_timestamp
    post_outlaw
    card = DB[:outlaw_cards].first
    refute_nil card[:created_at]
    assert_match(/\d{4}-\d{2}-\d{2}T/, card[:created_at])
  end
end
