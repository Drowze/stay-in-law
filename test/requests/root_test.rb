require_relative "../test_helper"

class RootTest < AppTest
  # ─── Helpers ──────────────────────────────────────────────────────────────

  def get_root(params = {})
    get "/", params, auth_header
  end

  def insert_token(minutes: 30)
    tok = SecureRandom.hex(2)
    id = DB[:qr_codes].insert(
      token: tok, minutes: minutes, created_at: Time.now.utc.iso8601
    )
    {id: id, token: tok, minutes: minutes}
  end

  # Inserts a scan and returns the scan id. Optionally pair with an outlaw card
  # to create a debt scan (redeemed_scan_id set on the card).
  def insert_scan(qr_code_id:, created_at: Time.now.utc.iso8601)
    DB[:scans].insert(qr_code_id: qr_code_id, created_at: created_at)
  end

  # Creates an active countdown by inserting a scan with a far-future expiry.
  def activate_countdown(minutes: 9999)
    qr = insert_token(minutes: minutes)
    insert_scan(qr_code_id: qr[:id])
  end

  def insert_outlaw_card(description: nil)
    DB[:outlaw_cards].insert(description: description, created_at: Time.now.utc.iso8601)
  end

  # ─── Auth ─────────────────────────────────────────────────────────────────

  def test_requires_basic_auth
    get "/"
    assert_equal 401, last_response.status
  end

  def test_returns_200_with_auth
    get_root
    assert_equal 200, last_response.status
  end

  # ─── Idle countdown ───────────────────────────────────────────────────────

  def test_shows_idle_countdown_when_no_scans
    get_root
    assert_includes last_response.body, "countdown-display-idle"
  end

  def test_shows_idle_prompt_when_no_scans_at_all
    get_root
    assert_includes last_response.body, "Nenhum QR code escaneado ainda"
  end

  def test_shows_scan_prompt_when_scans_exist_but_countdown_inactive
    qr = insert_token
    # past scan — countdown already expired
    past = (Time.now.utc - 3600).iso8601
    insert_scan(qr_code_id: qr[:id], created_at: past)
    get_root
    assert_includes last_response.body, "Escaneie um QR code"
  end

  # ─── Active countdown ─────────────────────────────────────────────────────

  def test_shows_active_countdown_when_running
    activate_countdown
    get_root
    assert_includes last_response.body, "countdown-display"
    refute_includes last_response.body, "countdown-display-idle"
  end

  def test_shows_finish_time_label_when_countdown_active
    activate_countdown
    get_root
    assert_includes last_response.body, "Termina às"
  end

  # ─── Debt warning ─────────────────────────────────────────────────────────

  def test_shows_debt_warning_when_debt_exists
    insert_outlaw_card
    get_root
    assert_includes last_response.body, "Você deve"
  end

  def test_does_not_show_debt_warning_when_no_debt
    get_root
    refute_includes last_response.body, "Você deve"
  end

  def test_debt_warning_shows_correct_count
    2.times { insert_outlaw_card }
    get_root
    assert_includes last_response.body, "2 QR codes"
  end

  # ─── Scan history ─────────────────────────────────────────────────────────

  def test_does_not_show_scan_list_when_no_scans
    get_root
    refute_includes last_response.body, "Últimos usos"
  end

  def test_shows_scan_history_when_scans_exist
    qr = insert_token
    insert_scan(qr_code_id: qr[:id])
    get_root
    assert_includes last_response.body, "Últimos usos"
  end

  def test_scan_history_shows_at_most_five_entries
    6.times do
      qr = insert_token
      insert_scan(qr_code_id: qr[:id])
    end
    get_root
    # each scan-list-item contains the class; count occurrences
    count = last_response.body.scan("scan-list-item").length
    assert_equal 5, count
  end

  # ─── Notice banners ───────────────────────────────────────────────────────

  def test_shows_success_time_added_notice
    get_root(notice: "success_time_added")
    assert_includes last_response.body, "Tempo adicionado"
  end

  def test_shows_success_debt_paid_notice
    get_root(notice: "success_debt_paid")
    assert_includes last_response.body, "quitar uma dívida"
  end

  def test_shows_failure_token_already_used_notice
    get_root(notice: "failure_token_already_used")
    assert_includes last_response.body, "já foi usado esta semana"
  end

  def test_shows_failure_countdown_active_notice
    get_root(notice: "failure_countdown_active")
    assert_includes last_response.body, "contagem regressiva"
  end

  def test_shows_failure_bad_scan_notice
    get_root(notice: "failure_bad_scan")
    assert_includes last_response.body, "QR code inválido"
  end

  def test_no_notice_banner_when_no_notice_param
    get_root
    # no notice alert should be rendered (only the JS selector string contains the class)
    refute_includes last_response.body, "alert is-auto-dismiss"
  end
end
