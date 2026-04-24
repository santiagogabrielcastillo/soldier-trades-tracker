---
title: "feat: Full i18n Support (English + Spanish)"
type: feat
status: active
date: 2026-04-23
---

# Full i18n Support (English + Spanish)

## Overview

Add complete internationalization to the app, extracting every hardcoded UI string into Rails locale YAML files for English (default) and Spanish. The user's chosen locale is stored in `UserPreference` (key `"locale"`) and applied on every request via `around_action :set_locale` in `ApplicationController`. A language switcher UI will be added in a follow-up task.

## Problem Statement

All ~59 views, controllers (flash messages), model validations, and mailers use hardcoded English strings. There is no `t()` call anywhere in the codebase. This blocks adding any second language.

## Proposed Solution

1. Add `rails-i18n` gem for built-in Spanish ActiveRecord / datetime / number translations.
2. Configure `config/application.rb` with `default_locale: :en`, `available_locales: [:en, :es]`, and `fallbacks: true`.
3. Add `around_action :set_locale` to `ApplicationController` — reads from `current_user.user_preferences.find_by(key: "locale")&.value`, falls back to `I18n.default_locale`.
4. Add a `LocaleController` (PATCH `/locale`) that saves the `UserPreference` and redirects back — wire up the button later.
5. Extract all hardcoded strings from views, layouts, controllers, models, and mailers into `config/locales/en.yml` and `config/locales/es.yml`.

## Technical Approach

### Architecture

- **Locale persistence:** `UserPreference` key `"locale"`, value `"en"` or `"es"` (jsonb column stores plain string). No DB migration needed.
- **Locale loading:** `around_action` (not `before_action`) so `I18n.locale` is reset after the request even on exceptions.
- **Unauthenticated requests:** Fall back to `I18n.default_locale` (`:en`) since auth pages don't need locale switching.
- **Fallbacks:** Enabled so missing Spanish keys silently fall back to English during rollout.
- **`rails-i18n` gem:** Provides Spanish translations for `activerecord.errors`, `date`, `time`, `number`, and `helpers` — eliminates ~200 internal Rails strings.
- **`TradesIndexColumns::LABELS`:** Ruby constant hash, not a view. Must use `I18n.t("trades_index_columns.#{id}")` instead of `t()` helper. Called at class load time today — must be refactored to a method that reads translations at call time.
- **HTML-in-flash messages:** Several controllers (stocks, spot, dashboards) embed `link_to` inside flash strings using `.html_safe`. Use Rails `_html` key suffix convention: `t("flash.some_key_html", link: link_to(...))` which auto-marks output as html_safe.
- **Mailer subject:** Change to `default subject: -> { I18n.t("mailers.users_mailer.password_reset.subject") }`. The mailer inherits `I18n.locale` from the request thread; for background mailers called from jobs, pass `locale:` explicitly.
- **Sync interval labels:** Used in two places in settings view as inline ternaries — extract to `t("sync_intervals.#{interval}")`.

### Locale YAML Structure

```yaml
# config/locales/en.yml
en:
  # Layouts
  nav:
    dashboard: "Dashboard"
    exchange_accounts: "Exchange accounts"
    trades: "Trades"
    spot: "Spot"
    stocks: "Stocks"
    companies: "Companies"
    allocation: "Allocation"
    settings: "Settings"
    admin_panel: "Admin panel →"
    sign_out: "Sign out"
    toggle_amounts: "Toggle amounts"

  # Flash messages
  flash:
    signed_in: "Signed in."
    signed_out: "Signed out."
    invalid_credentials: "Invalid email or password."
    not_authorized: "Not authorized."
    please_sign_in: "Please sign in."
    settings_saved: "Settings saved."
    sync_started: "Sync started. Trades will appear shortly."
    rate_limit: "Rate limit: max 2 syncs per day per account. Try again tomorrow."
    # ... (full list)

  # Sync intervals
  sync_intervals:
    hourly: "Hourly"
    daily: "Daily"
    twice_daily: "Twice daily (08:00 & 20:00 UTC)"

  # Dashboard
  dashboards:
    show:
      title: "Dashboard"
      subtitle: "Centralize your trade activity across exchanges."
      # ... (full list)

  # Per-controller sections follow same pattern
  # trades, exchange_accounts, settings, companies, portfolios, etc.

  # Trades index columns
  trades_index_columns:
    closed: "Closed"
    exchange: "Exchange"
    symbol: "Symbol"
    # ... (full list)

  # Mailers
  mailers:
    users_mailer:
      password_reset:
        subject: "Reset your password"
        # ... body keys

  # ActiveRecord model names / attributes (for form labels & error messages)
  activerecord:
    models:
      exchange_account: "Exchange account"
      # ...
    attributes:
      user:
        email: "Email"
        # ...
```

### Implementation Phases

#### Phase 1: Foundation

- Add `rails-i18n` gem to Gemfile
- Configure `config/application.rb` i18n settings
- Add `around_action :set_locale` in `ApplicationController`
- Create `LocaleController` with `update` action (PATCH `/locale`)
- Add `/locale` route
- Scaffold `config/locales/en.yml` and `config/locales/es.yml` with structure (content filled in phases 2-4)

**Files:**
- `Gemfile`
- `config/application.rb`
- `app/controllers/application_controller.rb`
- `app/controllers/locale_controller.rb` (new)
- `config/routes.rb`
- `config/locales/en.yml`
- `config/locales/es.yml`

#### Phase 2: Layouts + Auth Views

Extract strings from shared layouts and auth views — highest leverage as they appear on every page.

**Files:**
- `app/views/layouts/application.html.erb`
- `app/views/layouts/admin.html.erb`
- `app/views/sessions/new.html.erb`
- `app/views/users/new.html.erb`
- `app/views/password_resets/new.html.erb`
- `app/views/password_resets/edit.html.erb`
- `app/views/users_mailer/password_reset.html.erb`
- `app/views/users_mailer/password_reset.text.erb`
- `app/mailers/users_mailer.rb` (subject line)

#### Phase 3: Core App Views

Extract strings from the main functional views.

**Files (by section):**
- `app/views/dashboards/show.html.erb`
- `app/views/trades/index.html.erb`
- `app/views/exchange_accounts/` (3 files)
- `app/views/spot/` (4 files)
- `app/views/settings/` (3 files)
- `app/views/portfolios/` (4 files)
- `app/views/companies/` (6 files)
- `app/views/stocks/` (3 files)
- `app/views/allocations/` (2 files)
- `app/views/earnings_reports/` (4 files)
- `app/views/manual_trades/` (3 files)
- `app/views/stock_portfolios/` (4 files)
- `app/views/cedear_instruments/` (4 files)
- `app/views/admin/` (5 files)

#### Phase 4: Controllers, Models & Ruby-side Strings

Extract strings that live in Ruby files, not views.

**Files:**
- All controllers — flash `notice:` and `alert:` strings
- `app/models/trades_index_columns.rb` — `LABELS` hash → method using `I18n.t`
- `app/models/` — custom `errors.add` messages
- `app/models/user.rb`, `portfolio.rb`, `exchange_account.rb`, `earnings_report.rb`, `allocation_bucket.rb`, `custom_metric_value.rb`, `stock_portfolio.rb`

#### Phase 5: Spanish Translations

Fill in `config/locales/es.yml` with Spanish translations for all keys defined in phases 2–4.

This is the most time-consuming phase but purely mechanical — all keys exist in `en.yml` by this point.

## System-Wide Impact

### Interaction Graph

`ApplicationController#set_locale` fires as `around_action` on every request → sets `I18n.locale` → all `t()` calls in views/controllers/models resolve against it → `I18n.locale` reset after request completes. `LocaleController#update` writes `UserPreference(key: "locale")` → redirect. The `set_locale` action reads this preference on next request.

### Error & Failure Propagation

- If `UserPreference` DB query fails (rare), `&.value` returns `nil`, fallback to `I18n.default_locale` — safe.
- If a translation key is missing and fallbacks are enabled, Rails falls back to English — no crash, visible in logs as `I18n::MissingTranslationData` warning.
- Mailers called from Solid Queue jobs: `I18n.locale` defaults to `:en` in job context. For now this is acceptable since the only mailer is password reset (triggered from a request). If background mailers are added later, pass locale explicitly.

### State Lifecycle Risks

- `TradesIndexColumns::LABELS` is currently a Ruby constant evaluated at class load time. Converting to a method means each call hits `I18n.t` — negligible performance impact (translations are cached in memory). Must update all callers (`trades_index_columns.rb` callers in `app/models/trades_index_columns.rb` and any view that calls `.label`).
- `UserPreference` write on locale change: atomic single-row upsert — no consistency risk.

### API Surface Parity

- No JSON API endpoints in this app — all HTML responses. No API translation needed.
- Admin section has its own layout (`admin.html.erb`) — must be translated separately from main layout.

### Integration Test Scenarios

1. **Locale switches per request:** User sets `UserPreference(locale: "es")` → next page load shows Spanish nav labels.
2. **Unauthenticated fallback:** `/sessions/new` with no logged-in user → locale falls back to `:en`, page renders in English.
3. **Missing key fallback:** A key present in `en.yml` but missing from `es.yml` with Spanish locale set → renders English string (no exception).
4. **Flash message with interpolation:** Controller sets `notice: t("flash.ticker_added", ticker: "BTCUSDT")` → flash renders `"BTCUSDT added."` in English or `"BTCUSDT añadido."` in Spanish.
5. **TradesIndexColumns labels:** Column header labels render from `I18n.t` at request time, not from the boot-time constant — verified by switching locale mid-session.

## Acceptance Criteria

### Functional Requirements

- [ ] `config.i18n.default_locale = :en`, `available_locales: [:en, :es]`, `fallbacks: true` set in `application.rb`
- [ ] `rails-i18n` gem added and bundled
- [ ] `around_action :set_locale` in `ApplicationController` reads `UserPreference(key: "locale")` for authenticated users
- [ ] `LocaleController#update` (PATCH `/locale`) saves `UserPreference(key: "locale")` and redirects back
- [ ] Every hardcoded string in all 59 view files replaced with `t()` calls
- [ ] Every hardcoded string in controller flash messages replaced with `t()` calls
- [ ] Custom model `errors.add` messages extracted to `activerecord.errors` locale keys
- [ ] `TradesIndexColumns::LABELS` refactored to use `I18n.t` at call time
- [ ] Mailer subject uses `I18n.t`; body views use `t()` helpers
- [ ] `config/locales/en.yml` contains all extracted keys with English values
- [ ] `config/locales/es.yml` contains Spanish translations for all keys
- [ ] Switching locale via `LocaleController` persists and applies on next request
- [ ] Unauthenticated pages (auth forms) render in English regardless of user state

### Non-Functional Requirements

- [ ] No missing translation warnings in development logs for either locale
- [ ] Fallbacks enabled — missing Spanish keys silently render English
- [ ] Page layout does not break for Spanish strings (check for truncation in nav/buttons)

### Quality Gates

- [ ] All existing tests pass
- [ ] `bin/rails test` green after each phase
- [ ] Rubocop passes

## Dependencies & Prerequisites

- `rails-i18n` gem (adds Spanish ActiveRecord/date/number translations out of the box)
- No DB migrations required (`UserPreference` already exists with jsonb `value` column)
- Language switcher button UI is **out of scope** — deferred to follow-up task

## Risk Analysis & Mitigation

| Risk | Mitigation |
|------|-----------|
| Missing translation key causes `ActionView::Template::Error` in production | Enable `config.i18n.fallbacks = true` — falls back to English |
| Spanish strings longer than English break nav/button layout | Test with Spanish locale in browser after phase 2; adjust Tailwind truncation/wrapping as needed |
| `TradesIndexColumns::LABELS` refactor breaks column visibility feature | Grep all callers before changing; update tests |
| HTML-in-flash messages with `link_to` — `_html` suffix auto-escapes interpolated values | Use `html_safe` only on the translated string, not on the link interpolation; test XSS edge cases |
| Mailer locale in background jobs defaults to `:en` | Acceptable for now since only mailer is synchronous password reset; document for future background mailers |

## Sources & References

### Internal References

- `UserPreference` model: `app/models/user_preference.rb`
- `ApplicationController`: `app/controllers/application_controller.rb:7`
- Existing locale file: `config/locales/en.yml`
- `TradesIndexColumns::LABELS`: `app/models/trades_index_columns.rb:38`
- Flash with HTML: `app/controllers/stocks_controller.rb`, `app/controllers/spot_controller.rb`, `app/controllers/dashboards_controller.rb`

### External References

- Rails Internationalization Guide: https://guides.rubyonrails.org/i18n.html
- `rails-i18n` gem: https://github.com/svenfuchs/rails-i18n
