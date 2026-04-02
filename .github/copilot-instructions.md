# GitHub Copilot Instructions — stay-in-law

## Project overview

**stay-in-law** is a domestic screen-time tracker web app. Kids earn screen time by
scanning physical QR codes (once per week each). Parents (admins) manage QR codes and
can issue "outlaw card" penalties that must be repaid before the next QR code adds time.

## Tech stack

| Layer | Choice |
|---|---|
| Language | Ruby |
| Web framework | Sinatra (`~> 3.0`) — classic/top-level style, single `app.rb` |
| ORM | Sequel (`~> 5.0`) with SQLite (`sqlite3 ~> 1.7`) |
| Timezone | `tzinfo ~> 2.0` — always use `America/Sao_Paulo` (BRT, DST-aware) |
| Templates | ERB (Sinatra's built-in renderer) |
| Config | `dotenv ~> 2.8` — loaded at the top of `app.rb` via `require 'dotenv/load'` |
| Server | Puma (`~> 6.0`) via `config.ru` |
| Ruby compat | Ruby 4.0+ — `ostruct` and `logger` must be listed in the Gemfile |

**Frontend constraints — strictly no asset pipeline:**
- Plain CSS in `<style>` blocks inside ERB views
- Vanilla JavaScript in `<script>` blocks inside ERB views
- External libraries must be loaded from a **CDN only** (no npm, no bundlers)
- Current CDN dependencies: Google Fonts (Nunito), qrcodejs (`cdnjs.cloudflare.com`)

## Repository layout

```
app.rb              # All Sinatra routes and helpers (single file)
config.ru           # Rack entry point — just requires app.rb
db/schema.rb        # setup_database(db) — called once at boot, uses create_table?
views/
  layout.erb        # HTML shell, shared CSS (mobile-first, pastel theme)
  index.erb         # Landing page: countdown, debt warning, last-5 scans, admin links
  error.erb         # Generic error page (@message instance variable)
  admin/
    qr_codes.erb    # QR generation form + client-side QR rendering (qrcodejs)
    admin/outlaw.erb  # Outlaw card form + recent cards list
.env.example        # Documents all required environment variables
```

## Database schema

All timestamps are stored as **ISO-8601 UTC strings** (e.g. `"2024-01-15T14:30:00Z"`).
All user-facing time display is converted to BRT using `BRT.utc_to_local(utc_time)`.

```
qr_tokens
  id                    INTEGER PK
  token                 TEXT UNIQUE NOT NULL   -- SecureRandom.hex(16)
  minutes               INTEGER NOT NULL       -- 1–60, immutable after creation
  created_at            TEXT NOT NULL          -- ISO-8601 UTC
  last_used_week_start  TEXT                   -- 'YYYY-MM-DD' Monday in BRT; NULL = never used

scan_log
  id            INTEGER PK
  qr_token_id   INTEGER NOT NULL → qr_tokens.id
  scanned_at    TEXT NOT NULL                  -- ISO-8601 UTC
  # NOTE: minutes are NOT stored here; always join to qr_tokens to read them

outlaw_cards
  id                INTEGER PK
  description       TEXT                       -- optional, admin-supplied reason
  created_at        TEXT NOT NULL              -- ISO-8601 UTC
  redeemed_scan_id  INTEGER → scan_log.id      -- NULL = debt still owed
```

No `settings` table. The countdown end time is **always computed dynamically**:
find the most recent `scan_log` row that has no matching `outlaw_cards.redeemed_scan_id`,
then `countdown_end_at = scanned_at + qr_tokens.minutes * 60`.

## Environment variables

| Variable | Purpose |
|---|---|
| `BASIC_AUTH_USER` | HTTP Basic Auth username (shared by all pages) |
| `BASIC_AUTH_PASSWORD` | HTTP Basic Auth password |
| `SECURE_TOKEN` | Token required on admin POST endpoints (QR generation, outlaw cards) |
| `BASE_URL` | Origin used when building QR scan URLs (e.g. `https://example.com`) |
| `DATABASE_PATH` | SQLite file path (default: `db/app.db`) |

## Routes

| Method | Path | Auth | Notes |
|---|---|---|---|
| GET | `/` | Basic Auth | Landing page |
| GET | `/scan` | Token in QS | `?token=<hex>` — no Basic Auth |
| GET | `/admin/qr-codes` | Basic Auth | QR generation form |
| POST | `/admin/qr-codes` | Basic Auth + Secure Token | Returns **JSON** array |
| GET | `/admin/outlaw` | Basic Auth | Outlaw card form |
| POST | `/admin/outlaw` | Basic Auth + Secure Token | Standard form POST → redirect |

## Core business logic

### Week boundary (BRT)
```ruby
BRT = TZInfo::Timezone.get('America/Sao_Paulo')

def current_week_start_brt
  local     = BRT.utc_to_local(Time.now.utc)
  days_back = (local.wday - 1) % 7  # wday 0=Sun,1=Mon…; back to Monday
  monday    = local - (days_back * 86400)
  format('%04d-%02d-%02d', monday.year, monday.month, monday.day)
end
```

### Countdown computation
```ruby
def compute_countdown_end_at
  scan = DB[:scan_log]
    .join(:qr_tokens, id: :qr_token_id)
    .left_join(:outlaw_cards, redeemed_scan_id: Sequel[:scan_log][:id])
    .where(Sequel[:outlaw_cards][:id] => nil)          # anti-join: exclude debt scans
    .select(Sequel[:scan_log][:scanned_at], Sequel[:qr_tokens][:minutes])
    .order(Sequel.desc(Sequel[:scan_log][:scanned_at]))
    .first
  return nil unless scan
  Time.parse(scan[:scanned_at]) + (scan[:minutes] * 60)
end
```

### Scan endpoint logic (`GET /scan`)
1. Validate token exists in `qr_tokens`
2. Check `last_used_week_start != current_week_start_brt` (week lock)
3. Check countdown is not active (`compute_countdown_end_at <= Time.now.utc`)
4. Insert row in `scan_log`
5. Update `qr_tokens.last_used_week_start`
6. If `pending_debt_count > 0`: redeem oldest outlaw card → redirect `/?notice=debt_paid`
7. Else: redirect `/`

### Debt
- `pending_debt_count = DB[:outlaw_cards].where(redeemed_scan_id: nil).count`
- Each outlaw card represents 1 QR code owed
- On a debt scan: `UPDATE outlaw_cards SET redeemed_scan_id = <scan_id> WHERE id = <oldest>`
- The scan still goes into `scan_log` and still updates `last_used_week_start`
- The scan does NOT contribute to the countdown (it's excluded by the anti-join above)

## Helpers available in all routes and views

```ruby
protected!             # halts 401 with WWW-Authenticate if not authorized
authorized?            # returns bool; checks Rack Basic Auth against ENV vars
valid_secure_token?(t) # compares t against SECURE_TOKEN env var
current_week_start_brt # 'YYYY-MM-DD' of the current Monday in BRT
compute_countdown_end_at # Time (UTC) or nil
pending_debt_count     # Integer
utc_to_brt(t)          # converts UTC Time/string → TZInfo::LocalTime in BRT
format_brt(t)          # formats as 'DD/MM HH:MM' in BRT; returns '—' if nil
h(str)                 # HTML-escapes a string (alias for Rack::Utils.escape_html)
```

## View conventions

- **All views** use `views/layout.erb` automatically (Sinatra default)
- Pass data to views via `@instance_variables` set in the route block
- Use `<%= h(user_input) %>` for any user-supplied string rendered in HTML
- Render admin sub-views with `erb :'admin/qr_codes'` (symbol with path)
- Error page: set `@message` then `halt <status>, erb(:error)`
- Countdown end time is passed as `@countdown_end_at` (Ruby `Time` object, UTC);
  the view embeds it as `data-end="<%= @countdown_end_at.utc.iso8601 %>"` for JS

## CSS / design conventions

- **Mobile-first** — the landing page is the primary user surface (used by kids on phones)
- CSS is written inline in `views/layout.erb` using CSS custom properties (`--primary`, etc.)
- Colour palette: pastel pink/lavender (`--bg: #fdf2f8`, `--primary: #ec4899`, `--accent: #a855f7`)
- Typography: Nunito (Google Fonts CDN), weight 400/600/700/900
- Components: `.card` (white card with shadow), `.btn`, `.btn-primary`, `.alert`, `.field`
- Container: `max-width: 480px`, centred, `padding: 0 1rem`
- Admin pages are functional/minimal; landing page should be polished

## JavaScript conventions

- No frameworks, no modules — plain ES5/ES6 in `<script>` tags inside ERB views
- `fetch()` is used for the QR generation form (POST → JSON); use `credentials: 'same-origin'`
- Handle `res.status === 401` in fetch handlers by calling `window.location.reload()`
  (this re-triggers the browser's Basic Auth dialog)
- QR codes are rendered client-side by `new QRCode(element, { text, width, height })`
  using the qrcodejs library loaded from cdnjs
- Countdown ticks via `setInterval(tick, 1000)`; reads `new Date(el.dataset.end)` for target

## Sequel query patterns

Prefer qualified column identifiers in multi-table queries to avoid ambiguity:
```ruby
Sequel[:scan_log][:id]          # → scan_log.id
Sequel[:qr_tokens][:minutes]    # → qr_tokens.minutes
Sequel[:outlaw_cards][:id]      # → outlaw_cards.id (used for IS NULL anti-join check)
```

Join syntax:
```ruby
DB[:scan_log]
  .join(:qr_tokens, id: :qr_token_id)               # qr_tokens.id = scan_log.qr_token_id
  .left_join(:outlaw_cards, redeemed_scan_id: Sequel[:scan_log][:id])
  .where(Sequel[:outlaw_cards][:id] => nil)          # IS NULL anti-join
```

## Adding new features — checklist

- [ ] If adding a new page: protect with `protected!`; link from the landing page footer if user-facing
- [ ] If adding a new admin POST action: validate `valid_secure_token?(params[:secure_token])` before DB writes
- [ ] All new timestamps stored as `Time.now.utc.iso8601` (string, UTC)
- [ ] All new user-visible times displayed via `format_brt(...)` or `utc_to_brt(...).strftime(...)`
- [ ] No new gems that require compiled assets or a build step
- [ ] No new client-side libraries unless loaded from a CDN
- [ ] Keep `app.rb` as the single file for all routes and helpers
