# GitHub Copilot Instructions — stay-in-law

> **Maintenance note:** These instructions must be reviewed after every task and updated
> whenever routes, business logic, conventions, or file structure change. Outdated
> instructions are worse than no instructions — keep them accurate.

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
| Config | `dotenv ~> 2.8` — `app.rb` loads `.env.${RACK_ENV}` then `.env` via `Dotenv.load` |
| Server | Puma (`~> 6.0`) via `config.ru` |
| Ruby compat | Ruby 4.0+ — `ostruct` and `logger` must be listed in the Gemfile |

**Frontend constraints — strictly no asset pipeline:**
- All CSS lives in `public/css/app.css` — **never** write inline `style=` attributes or `<style>` blocks
- Vanilla JavaScript in `<script>` blocks inside ERB views
- External libraries must be loaded from a **CDN only** (no npm, no bundlers)
- Current CDN dependencies: Google Fonts (Nunito), qr-code-styling (`unpkg.com`)

## Repository layout

```
app.rb              # All Sinatra routes and helpers (single file)
config.ru           # Rack entry point — just requires app.rb
db/schema.rb        # setup_database(db) — called once at boot, uses create_table?
public/
  css/
    app.css         # All styles — the single source of CSS truth
views/
  layout.erb        # HTML shell: loads Nunito + app.css, yields content
  index.erb         # Landing page: countdown, debt warning, last-5 scans, admin links
  error.erb         # Generic error page (@message instance variable)
  admin/
    qr_codes.erb    # QR generation form + client-side QR rendering (qr-code-styling)
    outlaw.erb      # Outlaw card form + recent cards list
.env.example        # Documents all required environment variables
.env.test           # Test-environment overrides (committed; no secrets)
test/
  test_helper.rb    # Sets RACK_ENV=test, defines AppTest base class (Rack::Test)
  requests/         # Request (integration) tests
```

## Database schema

All timestamps are stored as **ISO-8601 UTC strings** (e.g. `"2024-01-15T14:30:00Z"`).
All user-facing time display is converted to BRT using `BRT.utc_to_local(utc_time)`.

```
qr_codes
  id                    INTEGER PK
  token                 TEXT UNIQUE NOT NULL   -- SecureRandom.hex(2), 4 hex chars
  minutes               INTEGER NOT NULL       -- 1–60, immutable after creation
  created_at            TEXT NOT NULL          -- ISO-8601 UTC
  last_used_week_start  TEXT                   -- 'YYYY-MM-DD' Monday in BRT; NULL = never used

scans
  id            INTEGER PK
  qr_code_id    INTEGER NOT NULL → qr_codes.id
  created_at    TEXT NOT NULL                  -- ISO-8601 UTC
  # NOTE: minutes are NOT stored here; always join to qr_codes to read them

outlaw_cards
  id                INTEGER PK
  description       TEXT                       -- optional, admin-supplied reason
  created_at        TEXT NOT NULL              -- ISO-8601 UTC
  redeemed_scan_id  INTEGER → scans.id         -- NULL = debt still owed
```

No `settings` table. The countdown end time is **always computed dynamically**:
find the most recent `scans` row that has no matching `outlaw_cards.redeemed_scan_id`,
then `countdown_end_at = scans.created_at + qr_codes.minutes * 60`.

## Environment variables

| Variable | Purpose |
|---|---|
| `BASIC_AUTH_USER` | HTTP Basic Auth username (shared by all pages) |
| `BASIC_AUTH_PASSWORD` | HTTP Basic Auth password |
| `SECURE_TOKEN` | Token required on admin POST endpoints (QR generation, outlaw cards) |

The SQLite DB path is derived automatically from `RACK_ENV`: `db/#{RACK_ENV}.db`
(e.g. `db/development.db`, `db/test.db`, `db/production.db`).

## Routes

| Method | Path | Auth | Notes |
|---|---|---|---|
| GET | `/` | Basic Auth | Landing page; also handles `?token=` scan trigger |
| POST | `/scans` | Basic Auth | Consume a QR token — returns JSON (see below) |
| GET | `/admin/qr_codes` | Basic Auth | QR generation form |
| POST | `/admin/qr_codes` | Basic Auth + Secure Token | Returns **JSON** array |
| GET | `/admin/outlaw_cards` | Basic Auth | Outlaw card form |
| POST | `/admin/outlaw_cards` | Basic Auth + Secure Token | Standard form POST → redirect |

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
  scan = DB[:scans]
    .join(:qr_codes, id: :qr_code_id)
    .left_join(:outlaw_cards, redeemed_scan_id: Sequel[:scans][:id])
    .where(Sequel[:outlaw_cards][:id] => nil)          # anti-join: exclude debt scans
    .select(Sequel[:scans][:created_at], Sequel[:qr_codes][:minutes])
    .order(Sequel.desc(Sequel[:scans][:created_at]))
    .first
  return nil unless scan
  Time.parse(scan[:created_at]) + (scan[:minutes] * 60)
end
```

### Scan endpoint logic (`POST /scans`)

Returns JSON. All error responses include `{error: "..."}`. The 422 responses also include a machine-readable `code` field.

1. Validate token exists in `qr_codes` → `403` if missing/invalid
2. Check `last_used_week_start != current_week_start_brt` → `422 {code: 'token_already_used'}` if already used
3. Check countdown is not active → `422 {code: 'countdown_active'}` if still running
4. Insert row in `scans`
5. Update `qr_codes.last_used_week_start`
6. If `pending_debt_count > 0`: redeem oldest outlaw card → `201 {id, qr_code: {...}, outlaw_card: {id, description}}`
7. Else: `201 {id, qr_code: {...}, outlaw_card: null}`

The landing page (`GET /`) detects `?token=` in the URL and auto-POSTs to `/scans` via `fetch()`, then reloads with a `?notice=` parameter:

| Notice | Trigger |
|---|---|
| `success_time_added` | 201 + `outlaw_card` is null |
| `success_debt_paid` | 201 + `outlaw_card` is present |
| `failure_token_already_used` | 422 `code: token_already_used` |
| `failure_countdown_active` | 422 `code: countdown_active` |
| `failure_bad_scan` | any other non-2xx (401 reloads silently to re-trigger Basic Auth) |

### Debt
- `pending_debt_count = DB[:outlaw_cards].where(redeemed_scan_id: nil).count`
- Each outlaw card represents 1 QR code owed
- On a debt scan: `UPDATE outlaw_cards SET redeemed_scan_id = <scan_id> WHERE id = <oldest>`
- The scan still goes into `scans` and still updates `last_used_week_start`
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

All styles live in **`public/css/app.css`** — the single source of CSS truth.
ERB views must not contain `<style>` blocks or `style=` attributes.

### Design tokens

Defined as CSS custom properties on `:root`:

| Token | Value | Use |
|---|---|---|
| `--bg` | `#fdf2f8` | Page background |
| `--card-bg` | `#ffffff` | Card surface |
| `--primary` | `#ec4899` | Primary pink — headings, buttons, active countdown |
| `--primary-soft` | `#fce7f3` | Focus ring fill |
| `--accent` | `#a855f7` | Accent purple — h2, finish time, QR minutes |
| `--text` | `#1e1b2e` | Body text |
| `--muted` | `#9b8fa6` | Secondary / hint text |
| `--border` | `#f3e0ec` | Dividers, input borders |
| `--warn` | `#f59e0b` | Warning / debt states |
| `--danger` | `#ef4444` | Error states |
| `--success` | `#10b981` | Success states |

### General rules

- **Mobile-first** — the landing page is the primary surface (used by kids on phones)
- Typography: Nunito (Google Fonts CDN), weights 400 / 600 / 700 / 900
- Container: `max-width: 480px`, centred, `padding: 1.25rem 1rem 2rem`
- Admin pages are functional/minimal; the landing page should be polished

### Class inventory

`app.css` is organised into labelled sections. Add new rules in the appropriate section,
or create a new clearly labelled section — do not append rules at the end of unrelated sections.

**Layout**
- `.container` — centred page wrapper (max 480 px)
- `.container-centered` — adds flex centering for full-height pages (error page)

**Card**
- `.card` — white rounded card with shadow
- `.card-hero` — variant with centred text and larger padding (countdown, error)

**Button**
- `.btn` — base pill button
- `.btn-primary` — pink fill
- `.btn-block` — full-width

**Form**
- `.field` — wraps label + input with bottom margin
- Input/textarea styles are applied via element selectors (no extra class needed)

**Alert**
- `.alert` — base alert bar
- `.alert-warn` / `.alert-danger` / `.alert-success` — colour modifiers

**Navigation**
- `.page-header` — top padding area used on admin pages
- `.back-link` — the "← início" link style
- `.site-header` — centred header used on the landing page

**Landing page — countdown**
- `.countdown-label` — "TEMPO RESTANTE" uppercase label
- `.countdown-display` — the large ticking HH:MM:SS digits (active, pink)
- `.countdown-display-idle` — same size but greyed out when no countdown is running
- `.countdown-subtext` — text below the digits (finish time or idle prompt)
- `.countdown-finish-time` — accent-coloured finish time value

**Landing page — scan history**
- `.scan-list` / `.scan-list-item` — the last-5 scans list and its rows
- `.scan-timestamp` — muted left-hand timestamp
- `.scan-minutes` — bold pink right-hand minute count (normal scan)
- `.scan-minutes-debt` — struck-through warn-coloured minutes (debt scan)
- `.scan-debt-label` — small "(dívida)" tag

**Landing page — footer**
- `.admin-footer` / `.admin-footer-label` — small admin links at the bottom

**Error page**
- `.error-inner` — full-width centred wrapper
- `.error-icon` / `.error-title` / `.error-message` — emoji, heading, body

**Admin — QR code results**
- `.qr-results-heading` — the "QR Codes Gerados" h2 with tighter top margin
- `.qr-results-header` — flex row containing the "QR Codes Gerados" heading and the print button
- `.qr-print-btn` — the "🖨️ Imprimir" button shown after generation
- `.qr-card` — dynamically created card per QR code (added via JS alongside `.card`)
- `.qr-image` — inline-block wrapper for the qr-code-styling canvas
- `.qr-info` / `.qr-info-minutes` — URL text and highlighted minute count

**Admin — outlaw card history**
- `.outlaw-list` / `.outlaw-list-item` — list and its rows
- `.outlaw-list-item-header` — flex row containing date + status badge
- `.outlaw-date` — muted small timestamp
- `.outlaw-status` — base badge; paired with `.outlaw-status-redeemed` or `.outlaw-status-pending`
- `.outlaw-description` — italic description text

**Utilities**
- `.is-hidden` — `display: none !important` — toggled by JS with `classList.add/remove('is-hidden')`
- `.is-fading` — triggers the CSS opacity-transition fade-out animation (added by JS before removal)
- `.is-auto-dismiss` — marks a notice element for automatic fade-out after 4 s (handled by shared JS in `index.erb`)

## JavaScript conventions

- No frameworks, no modules — plain ES5/ES6 in `<script>` blocks inside ERB views
- **Never use `element.style.*` or `element.style.cssText`** — use `classList` and CSS classes instead
- Toggle visibility with `classList.add('is-hidden')` / `classList.remove('is-hidden')`
- Trigger fade-out with `classList.add('is-fading')`, then `remove()` the element after 500 ms
- `fetch()` is used for the QR generation form (POST → JSON) and for scan submissions from the landing page (POST → JSON); always use `credentials: 'same-origin'`
- Handle `res.status === 401` in fetch handlers by calling `window.location.reload()`
  (this re-triggers the browser's Basic Auth dialog)
- QR codes are rendered client-side by `new QRCode(element, { text, width, height })`
  using the qr-code-styling library loaded from unpkg.com
- Countdown ticks via `setInterval(tick, 1000)`; reads `new Date(el.dataset.end)` for target

## Sequel query patterns

Prefer qualified column identifiers in multi-table queries to avoid ambiguity:
```ruby
Sequel[:scans][:id]             # → scans.id
Sequel[:qr_codes][:minutes]     # → qr_codes.minutes
Sequel[:outlaw_cards][:id]      # → outlaw_cards.id (used for IS NULL anti-join check)
```

Join syntax:
```ruby
DB[:scans]
  .join(:qr_codes, id: :qr_code_id)                     # qr_codes.id = scans.qr_code_id
  .left_join(:outlaw_cards, redeemed_scan_id: Sequel[:scans][:id])
  .where(Sequel[:outlaw_cards][:id] => nil)              # IS NULL anti-join
```

## Docker

The app ships with a `Dockerfile` based on `ruby:3.3-alpine`. Key design decisions:

- `tzdata` is installed so `TZInfo` can resolve `America/Sao_Paulo` on Alpine.
- A dedicated system user/group `app` is created and set as `USER` immediately, so all subsequent layers (`WORKDIR`, `COPY`, `bundle install`) run as non-root.
- `test` group gems are excluded from the production image (`bundle config set --local without 'test'`).
- The SQLite database is **not** baked into the image — mount a host directory to `/app/db` to persist data across container restarts.

### Building

```bash
docker build -t stay-in-law .
```

### Running

```bash
docker run -d \
  -p 4567:4567 \
  -v /path/to/data:/app/db \
  -e BASIC_AUTH_USER=youruser \
  -e BASIC_AUTH_PASSWORD=yourpassword \
  -e SECURE_TOKEN=yoursecrettoken \
  --name stay-in-law \
  stay-in-law
```

All required env vars (`BASIC_AUTH_USER`, `BASIC_AUTH_PASSWORD`, `SECURE_TOKEN`) must be provided at runtime — there is no `.env` file inside the image. The app listens on port `4567`.

## Adding new features — checklist

- [ ] If adding a new page: protect with `protected!`; link from the landing page footer if user-facing
- [ ] If adding a new admin POST action: validate `valid_secure_token?(params[:secure_token])` before DB writes
- [ ] All new timestamps stored as `Time.now.utc.iso8601` (string, UTC)
- [ ] All new user-visible times displayed via `format_brt(...)` or `utc_to_brt(...).strftime(...)`
- [ ] No new gems that require compiled assets or a build step
- [ ] No new client-side libraries unless loaded from a CDN
- [ ] Keep `app.rb` as the single file for all routes and helpers
- [ ] All new CSS goes into `public/css/app.css` in the appropriate labelled section — no inline `style=` attributes, no `<style>` blocks
- [ ] All new JS visibility/state changes use `classList` — never `element.style.*`
