require_relative '../../test_helper'

class QrCodesRequestTest < AppTest
  # ─── Helpers ──────────────────────────────────────────────────────────────

  # Issues POST /admin/qr_codes with sensible defaults; override any param as needed.
  def post_qr_codes(params = {})
    defaults = { count: '3', minutes: '15', secure_token: ENV['SECURE_TOKEN'] }
    post '/admin/qr_codes', defaults.merge(params), auth_header
  end

  def parsed_body
    JSON.parse(last_response.body)
  end

  # ─── Success cases ────────────────────────────────────────────────────────

  def test_returns_200_with_json_array
    post_qr_codes
    assert_equal 200, last_response.status
    assert_equal 'application/json', last_response.content_type
    assert_kind_of Array, parsed_body
  end

  def test_generates_the_requested_number_of_codes
    post_qr_codes(count: '5')
    assert_equal 5, parsed_body.length
  end

  def test_persists_exactly_that_many_tokens_in_the_database
    post_qr_codes(count: '4')
    assert_equal 4, DB[:qr_codes].count
  end

  def test_each_code_carries_the_requested_minutes_value
    post_qr_codes(count: '3', minutes: '45')
    parsed_body.each do |qr|
      assert_equal 45, qr['minutes']
    end
  end

  def test_database_records_store_the_correct_minutes_value
    post_qr_codes(count: '2', minutes: '30')
    DB[:qr_codes].all.each do |row|
      assert_equal 30, row[:minutes]
    end
  end

  def test_each_code_contains_a_valid_hex_token
    post_qr_codes(count: '3')
    parsed_body.each do |qr|
      assert_match(/\A[0-9a-f]{4}\z/, qr['token'],
        "Expected a 4-char hex token, got: #{qr['token']}")
    end
  end

  def test_all_generated_tokens_are_unique
    post_qr_codes(count: '10')
    tokens = parsed_body.map { |qr| qr['token'] }
    assert_equal tokens.length, tokens.uniq.length
  end

  def test_response_does_not_include_scan_url
    post_qr_codes(count: '1', minutes: '20')
    qr = parsed_body.first
    assert_nil qr['scan_url']
  end

  def test_tokens_are_stored_in_the_database_matching_the_response
    post_qr_codes(count: '3', minutes: '10')
    parsed_body.each do |qr|
      db_row = DB[:qr_codes].where(token: qr['token']).first
      refute_nil db_row, "Token #{qr['token']} not found in qr_codes"
      assert_equal qr['minutes'], db_row[:minutes]
    end
  end

  def test_new_tokens_have_null_last_used_week_start
    post_qr_codes(count: '2')
    DB[:qr_codes].all.each do |row|
      assert_nil row[:last_used_week_start]
    end
  end

  # ─── Auth / security ──────────────────────────────────────────────────────

  def test_requires_basic_auth
    post '/admin/qr_codes', { count: '1', minutes: '10', secure_token: ENV['SECURE_TOKEN'] }
    assert_equal 401, last_response.status
  end

  def test_rejects_missing_secure_token
    post_qr_codes(secure_token: '')
    assert_equal 403, last_response.status
    assert_equal 'Token de segurança inválido.', parsed_body['error']
  end

  def test_rejects_wrong_secure_token
    post_qr_codes(secure_token: 'definitely-wrong')
    assert_equal 403, last_response.status
  end

  def test_does_not_create_tokens_when_secure_token_is_wrong
    post_qr_codes(secure_token: 'definitely-wrong')
    assert_equal 0, DB[:qr_codes].count
  end

  # ─── Validation ───────────────────────────────────────────────────────────

  def test_rejects_count_of_zero
    post_qr_codes(count: '0')
    assert_equal 422, last_response.status
  end

  def test_rejects_count_above_fifty
    post_qr_codes(count: '51')
    assert_equal 422, last_response.status
  end

  def test_rejects_minutes_of_zero
    post_qr_codes(minutes: '0')
    assert_equal 422, last_response.status
  end

  def test_rejects_minutes_above_sixty
    post_qr_codes(minutes: '61')
    assert_equal 422, last_response.status
  end

  def test_validation_error_returns_json_with_error_key
    post_qr_codes(count: '0')
    assert_kind_of String, parsed_body['error']
    refute_empty parsed_body['error']
  end

  def test_does_not_create_tokens_on_validation_error
    post_qr_codes(count: '51')
    assert_equal 0, DB[:qr_codes].count
  end

  # ─── Boundary values ──────────────────────────────────────────────────────

  def test_accepts_minimum_count_of_one
    post_qr_codes(count: '1')
    assert_equal 200, last_response.status
    assert_equal 1, parsed_body.length
  end

  def test_accepts_maximum_count_of_fifty
    post_qr_codes(count: '50')
    assert_equal 200, last_response.status
    assert_equal 50, parsed_body.length
  end

  def test_accepts_minimum_minutes_of_one
    post_qr_codes(minutes: '1')
    assert_equal 200, last_response.status
    assert_equal 1, parsed_body.first['minutes']
  end

  def test_accepts_maximum_minutes_of_sixty
    post_qr_codes(minutes: '60')
    assert_equal 200, last_response.status
    assert_equal 60, parsed_body.first['minutes']
  end

  # ─── GET /admin/qr_codes ──────────────────────────────────────────────────

  def test_get_returns_200_with_auth
    get '/admin/qr_codes', {}, auth_header
    assert_equal 200, last_response.status
  end

  def test_get_requires_basic_auth
    get '/admin/qr_codes'
    assert_equal 401, last_response.status
  end
end
