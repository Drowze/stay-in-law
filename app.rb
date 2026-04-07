require 'sinatra'
require 'sequel'
require 'json'
require 'securerandom'
require 'time'
require 'tzinfo'
require 'fileutils'
require 'dotenv'
Dotenv.load(".env.#{ENV.fetch('RACK_ENV', 'development')}", '.env')

require_relative 'db/schema'

# ─── Database ─────────────────────────────────────────────────────────────────

DB_PATH = "db/#{ENV.fetch('RACK_ENV', 'development')}.db"
FileUtils.mkdir_p(File.dirname(DB_PATH))
DB = Sequel.connect("sqlite://#{DB_PATH}")
setup_database(DB)

BRT = TZInfo::Timezone.get('America/Sao_Paulo')

# ─── Sinatra config ───────────────────────────────────────────────────────────

configure do
  set :views, File.join(__dir__, 'views')
end

# ─── Helpers ──────────────────────────────────────────────────────────────────

helpers do
  include Rack::Utils
  alias_method :h, :escape_html

  def protected!
    return if authorized?
    headers['WWW-Authenticate'] = 'Basic realm="Stay in Law"'
    halt 401, 'Not authorized'
  end

  def authorized?
    @auth ||= Rack::Auth::Basic::Request.new(request.env)
    @auth.provided? && @auth.basic? && @auth.credentials &&
      @auth.credentials[0] == ENV.fetch('BASIC_AUTH_USER', 'admin') &&
      @auth.credentials[1] == ENV.fetch('BASIC_AUTH_PASSWORD', 'changeme')
  end

  def valid_secure_token?(token)
    expected = ENV.fetch('SECURE_TOKEN', '')
    !expected.empty? && token.to_s == expected
  end

  # Returns 'YYYY-MM-DD' string for the Monday that started the current BRT week.
  def current_week_start_brt
    local     = BRT.utc_to_local(Time.now.utc)
    days_back = (local.wday - 1) % 7  # wday: 0=Sun,1=Mon,…,6=Sat → days to subtract to reach Monday
    monday    = local - (days_back * 86400)
    format('%04d-%02d-%02d', monday.year, monday.month, monday.day)
  end

  # Returns a Time (UTC) when the countdown expires, or nil when no active/recent countdown.
  # Finds the most recent scan that was NOT used to pay off an outlaw-card debt,
  # then computes scanned_at + qr_tokens.minutes.
  def compute_countdown_end_at
    scan = DB[:scan_log]
      .join(:qr_tokens, id: :qr_token_id)
      .left_join(:outlaw_cards, redeemed_scan_id: Sequel[:scan_log][:id])
      .where(Sequel[:outlaw_cards][:id] => nil)
      .select(
        Sequel[:scan_log][:scanned_at],
        Sequel[:qr_tokens][:minutes]
      )
      .order(Sequel.desc(Sequel[:scan_log][:scanned_at]))
      .first

    return nil unless scan

    Time.parse(scan[:scanned_at]) + (scan[:minutes] * 60)
  end

  def pending_debt_count
    DB[:outlaw_cards].where(redeemed_scan_id: nil).count
  end

  def utc_to_brt(time_or_str)
    return nil unless time_or_str
    utc = time_or_str.is_a?(Time) ? time_or_str.utc : Time.parse(time_or_str.to_s).utc
    BRT.utc_to_local(utc)
  end

  def format_brt(time_or_str)
    t = utc_to_brt(time_or_str)
    return '—' unless t
    t.strftime('%d/%m %H:%M')
  end
end

# ─── Routes ───────────────────────────────────────────────────────────────────

get '/' do
  protected!

  @countdown_end_at = compute_countdown_end_at
  @countdown_active = @countdown_end_at && @countdown_end_at > Time.now.utc
  @pending_debt     = pending_debt_count
  @notice           = params[:notice]

  @recent_scans = DB[:scan_log]
    .join(:qr_tokens, id: :qr_token_id)
    .left_join(:outlaw_cards, redeemed_scan_id: Sequel[:scan_log][:id])
    .select(
      Sequel[:scan_log][:scanned_at],
      Sequel[:qr_tokens][:minutes],
      Sequel[:outlaw_cards][:id].as(:outlaw_card_id)
    )
    .order(Sequel.desc(Sequel[:scan_log][:scanned_at]))
    .limit(5)
    .all

  erb :index
end

get '/scan' do
  token_str = params[:token].to_s.strip

  if token_str.empty?
    @message = 'QR code inválido.'
    halt 403, erb(:error)
  end

  qr = DB[:qr_tokens].where(token: token_str).first
  unless qr
    @message = 'QR code inválido.'
    halt 403, erb(:error)
  end

  week_start = current_week_start_brt
  if qr[:last_used_week_start] == week_start
    @message = 'Este QR code já foi usado esta semana. Tente outro!'
    halt 403, erb(:error)
  end

  countdown_end_at = compute_countdown_end_at
  if countdown_end_at && countdown_end_at > Time.now.utc
    @message = 'A contagem regressiva ainda está ativa. Aguarde terminar antes de escanear um novo QR code.'
    halt 403, erb(:error)
  end

  now_utc = Time.now.utc.iso8601
  scan_id = DB[:scan_log].insert(
    qr_token_id: qr[:id],
    scanned_at:  now_utc
  )

  DB[:qr_tokens].where(id: qr[:id]).update(last_used_week_start: week_start)

  oldest_debt = DB[:outlaw_cards].where(redeemed_scan_id: nil).order(:created_at).first
  if oldest_debt
    DB[:outlaw_cards].where(id: oldest_debt[:id]).update(redeemed_scan_id: scan_id)
    redirect '/?notice=debt_paid'
  else
    redirect '/'
  end
end

# Admin – QR code generation

get '/admin/qr-codes' do
  protected!
  erb :'admin/qr_codes'
end

post '/admin/qr-codes' do
  protected!
  content_type :json

  unless valid_secure_token?(params[:secure_token])
    halt 403, { error: 'Token de segurança inválido.' }.to_json
  end

  count   = params[:count].to_i
  minutes = params[:minutes].to_i

  unless (1..50).cover?(count)
    halt 422, { error: 'A quantidade deve estar entre 1 e 50.' }.to_json
  end

  unless (1..60).cover?(minutes)
    halt 422, { error: 'Os minutos devem estar entre 1 e 60.' }.to_json
  end

  base_url = ENV.fetch('BASE_URL', "#{request.scheme}://#{request.host_with_port}")
  now_utc  = Time.now.utc.iso8601

  tokens = count.times.map do
    tok = SecureRandom.hex(2)
    DB[:qr_tokens].insert(token: tok, minutes: minutes, created_at: now_utc)
    { token: tok, scan_url: "#{base_url}/scan?token=#{tok}", minutes: minutes }
  end

  tokens.to_json
end

# Admin – Outlaw cards

get '/admin/outlaw' do
  protected!
  @pending_debt = pending_debt_count
  @recent_cards = DB[:outlaw_cards].order(Sequel.desc(:created_at)).limit(10).all
  @success      = params[:success] == '1'
  erb :'admin/outlaw'
end

post '/admin/outlaw' do
  protected!

  unless valid_secure_token?(params[:secure_token])
    @message = 'Token de segurança inválido.'
    halt 403, erb(:error)
  end

  desc = params[:description].to_s.strip
  desc = nil if desc.empty?

  DB[:outlaw_cards].insert(
    description: desc,
    created_at:  Time.now.utc.iso8601
  )

  redirect '/admin/outlaw?success=1'
end
