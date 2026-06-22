require "test_helper"

class RootTest < ActionDispatch::IntegrationTest
  def get_root(params = {})
    get root_path, params: params, headers: auth_headers
  end

  def insert_token(minutes: 30)
    qr = QrCode.create!(token: SecureRandom.hex(2), minutes: minutes, created_at: Time.current.utc)
    {id: qr.id, token: qr.token, minutes: qr.minutes}
  end

  def insert_scan(qr_code_id:, created_at: Time.current.utc)
    Scan.create!(qr_code_id: qr_code_id, created_at: created_at)
  end

  def activate_countdown(minutes: 60)
    qr = insert_token(minutes: minutes)
    insert_scan(qr_code_id: qr[:id])
  end

  def insert_outlaw_card(description: nil)
    OutlawCard.create!(description: description, created_at: Time.current.utc)
  end

  def test_requires_basic_auth
    get root_path
    assert_response :unauthorized
  end

  def test_returns_200_with_auth
    get_root
    assert_response :success
  end

  def test_shows_idle_countdown_when_no_scans
    get_root
    assert_includes response.body, "countdown-display-idle"
  end

  def test_shows_idle_prompt_when_no_scans_at_all
    get_root
    assert_includes response.body, "Nenhum QR code escaneado ainda"
  end

  def test_shows_scan_prompt_when_scans_exist_but_countdown_inactive
    qr = insert_token
    insert_scan(qr_code_id: qr[:id], created_at: 1.hour.ago.utc)
    get_root
    assert_includes response.body, "Escaneie um QR code"
  end

  def test_shows_active_countdown_when_running
    activate_countdown
    get_root
    assert_includes response.body, "countdown-display"
    refute_includes response.body, "countdown-display-idle"
  end

  def test_shows_finish_time_label_when_countdown_active
    activate_countdown
    get_root
    assert_includes response.body, "Termina às"
  end

  def test_shows_debt_warning_when_debt_exists
    insert_outlaw_card
    get_root
    assert_includes response.body, "Você deve"
  end

  def test_does_not_show_debt_warning_when_no_debt
    get_root
    refute_includes response.body, "Você deve"
  end

  def test_debt_warning_shows_correct_count
    2.times { insert_outlaw_card }
    get_root
    assert_includes response.body, "2 QR codes"
  end

  def test_does_not_show_scan_list_when_no_scans
    get_root
    refute_includes response.body, "Últimos usos"
  end

  def test_shows_scan_history_when_scans_exist
    qr = insert_token
    insert_scan(qr_code_id: qr[:id])
    get_root
    assert_includes response.body, "Últimos usos"
  end

  def test_scan_history_shows_at_most_five_entries
    6.times do
      qr = insert_token
      insert_scan(qr_code_id: qr[:id])
    end

    get_root
    assert_equal 5, response.body.scan("scan-list-item").length
  end

  def test_shows_success_time_added_notice
    get_root(notice: "success_time_added")
    assert_includes response.body, "Tempo adicionado"
  end

  def test_shows_success_debt_paid_notice
    get_root(notice: "success_debt_paid")
    assert_includes response.body, "quitar uma dívida"
  end

  def test_shows_failure_token_already_used_notice
    get_root(notice: "failure_token_already_used")
    assert_includes response.body, "já foi usado esta semana"
  end

  def test_shows_failure_countdown_active_notice
    get_root(notice: "failure_countdown_active")
    assert_includes response.body, "contagem regressiva"
  end

  def test_shows_failure_bad_scan_notice
    get_root(notice: "failure_bad_scan")
    assert_includes response.body, "QR code inválido"
  end
end
