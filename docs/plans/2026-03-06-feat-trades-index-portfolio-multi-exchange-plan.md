# feat: Trades index multi-exchange tabs, History filters, Portfolio exchange scope

---
title: Trades index multi-exchange tabs, History filters, Portfolio exchange scope
type: feat
status: completed
date: 2026-03-06
source_brainstorm: docs/brainstorms/2026-03-06-trades-index-portfolio-multi-exchange-brainstorm.md
---

## Enhancement Summary

**Deepened on:** 2026-03-06  
**Sections enhanced:** Overview, Phase 1 (Portfolio), Phase 2 (IndexService/controller), Phase 3 (UI), Technical Notes.  
**Research sources:** Rails optional FK migrations, IDOR prevention via user-scoped lookups, GET param preservation with Pagy and forms, ExchangeAccount destroy behavior.

### Key improvements

1. **Migration:** Use `add_reference` (reversible); optional `on_delete: :nullify` on FK; add `ExchangeAccount has_many :portfolios, dependent: :nullify` so deleting an account nullifies portfolio references instead of raising.
2. **Security:** Resolve `exchange_account_id` only via `current_user.exchange_accounts.find_by(id: ...)`; when invalid for exchange tab, redirect to history with flash (no 404 leak). Service receives pre-scoped id from controller.
3. **URL/state:** Single helper `trades_index_filter_params` (permitted keys) for filter form action, tab links, and optional redirect after column-preference PATCH. Pagy preserves GET params by default for index; no custom `pagy_url_for` needed.
4. **Portfolio form:** When permitting `exchange_account_id`, resolve via `current_user.exchange_accounts` before assign (or validate ownership in model); support optional `on_delete: :nullify` in migration for DB consistency.

### New considerations discovered

- **Data integrity:** Deleting an `ExchangeAccount` that portfolios reference: use `dependent: :nullify` on `ExchangeAccount` and optionally `on_delete: :nullify` in the FK so DB and Rails agree.
- **Authorization:** Never use raw `params[:exchange_account_id]` for queries; always resolve through `current_user.exchange_accounts` so the dataset constraint prevents IDOR.
- **Column modal redirect:** `UserPreferencesController` (or column update action) should redirect to `trades_path(permitted_context_params)` so the URL after "Save" keeps view/tab and filters.

---

## Overview

Rework the trades index and portfolio so that: (1) **History** has filters for date range and exchange(s); (2) there is **one tab per linked exchange account** (e.g. History | Binance | BingX | Portfolio), each showing that account's trades with an optional date filter; (3) **Portfolio** can optionally scope to a single exchange so "portfolio view" is not mixing both exchanges. URL params preserve view, filters, and selected tab for refresh/share.

## Problem Statement / Motivation

- With Binance and BingX linked, the trades index shows all trades mixed; there is no way to see "only Binance" or "only BingX" without a dedicated view.
- Portfolio is a date window over all user trades; selecting a portfolio still shows both exchanges' trades in one table.
- Users need to filter History by date and/or exchange, and to have a clear per-exchange view and an optional exchange scope on portfolios.

## Proposed Solution

1. **Portfolio: optional exchange scope**
   - Add nullable `exchange_account_id` to `portfolios` (FK to `exchange_accounts`). Validate that the account belongs to the portfolio's user.
   - `Portfolio#trades_in_range`: when `exchange_account_id` is set, restrict to that account's trades within the date range; when null, keep current behavior (all user trades in range).
   - Portfolio form: "Include trades from: [All exchanges | Binance | BingX]" (options from user's exchange accounts). Existing portfolios stay "all exchanges" (null).

2. **Trades index: view types and params**
   - **View param:** `history` | `portfolio` | `exchange`. Default when no view: keep current (redirect to default portfolio if set, else History).
   - **New params:** `exchange_account_id` (for exchange tab and optional History filter), `from_date`, `to_date` (optional; applied on History and exchange tab).
   - **History:** Load all user trades; apply optional `from_date`/`to_date` and optional `exchange_account_id` (single: filter to that account). Same positions table and columns.
   - **Exchange tab:** Require `exchange_account_id` (must be one of current_user's exchange_accounts). Load that account's trades; apply optional `from_date`/`to_date`. Same table/columns.
   - **Portfolio:** Unchanged logic except trades come from `portfolio.trades_in_range`, which now respects portfolio's `exchange_account_id` when set.

3. **Trades index UI**
   - **Tabs:** History | [one link per `current_user.exchange_accounts`] | Portfolio. Exchange tab label: account's `provider_type` (e.g. "Binance", "BingX"). Link: `trades_path(view: "exchange", exchange_account_id: account.id)`. Active: `@view == "exchange" && @exchange_account&.id == account.id`.
   - **History:** Filter bar with from date, to date, and "Exchange" select (All exchanges | Binance | BingX). GET form; preserve `view=history` and filter params on submit and in pagination links.
   - **Exchange tab:** Filter bar with from date, to date only (exchange is fixed by tab). GET form; preserve `view=exchange`, `exchange_account_id`, and date params.
   - **Portfolio:** Existing selector; when portfolio has an exchange set, show it in the summary line (e.g. "· Binance only").
   - **Empty state:** When `view == "exchange"` and no positions: "No trades for this exchange." Optional: link to "Sync" or exchange accounts page.
   - **Column modal:** Preserve `view`, `exchange_account_id`, `from_date`, `to_date`, `portfolio_id` in hidden fields when saving column preference so context is not lost.

4. **URL/state**
   - All links and forms use GET with `view`, `exchange_account_id`, `from_date`, `to_date`, `portfolio_id` as appropriate so the active tab and filters are reflected in the URL and survive refresh.

5. **Dashboard**
   - No code change. Dashboard already uses `default_portfolio.trades_in_range`; once `trades_in_range` scopes by `exchange_account_id` when set, the dashboard summary will automatically respect the portfolio's exchange scope.

---

## Implementation Phases

### Phase 1: Portfolio optional exchange scope

- [x] Migration: add `exchange_account_id` (bigint, null: true, FK to `exchange_accounts`) to `portfolios`. Index for lookups. Ensure exchange_accounts belongs to same user when present (application-level validation).
- [x] `Portfolio` model: `belongs_to :exchange_account, optional: true`. Validation: when `exchange_account_id` present, `exchange_account` must be in `user.exchange_accounts` (e.g. `validate :exchange_account_belongs_to_user`).
- [x] `Portfolio#trades_in_range`: base relation remains `user.trades` in date range; when `exchange_account_id.present?` add `.where(exchange_account_id: exchange_account_id)`.
- [x] `PortfoliosController#portfolio_params`: permit `:exchange_account_id` (allow blank for "All exchanges").
- [x] Portfolio form (`_form.html.erb`): add "Include trades from" select. Options: blank option "All exchanges", then `current_user.exchange_accounts` with id and label (e.g. `account.provider_type.to_s.capitalize`). Value = id or blank.
- [x] Trades index (portfolio view): in the summary line next to portfolio date range, when `@portfolio.exchange_account.present?` show e.g. "· Binance only" (or provider_type label).
- [x] `ExchangeAccount` model: add `has_many :portfolios, dependent: :nullify` so destroying an account nullifies portfolio references instead of raising FK error.

**Files to add/change:** `db/migrate/..._add_exchange_account_id_to_portfolios.rb`, `app/models/portfolio.rb`, `app/models/exchange_account.rb`, `app/controllers/portfolios_controller.rb`, `app/views/portfolios/_form.html.erb`, `app/views/trades/index.html.erb` (portfolio summary line).

#### Research insights (Phase 1)

**Migration:** Use `add_reference` for reversibility; keep `null: true`; add FK with optional `on_delete: :nullify` so DB-level deletes nullify the column. Rollback is `remove_reference :portfolios, :exchange_account, foreign_key: true`.

```ruby
# db/migrate/YYYYMMDDHHMMSS_add_exchange_account_id_to_portfolios.rb
add_reference :portfolios, :exchange_account,
              null: true,
              foreign_key: { to_table: :exchange_accounts, on_delete: :nullify }
```

**Ownership validation:** In `Portfolio`, validate that `exchange_account_id` is in `user.exchange_accounts` when present (e.g. `validate :exchange_account_belongs_to_user, if: :exchange_account_id?`); use `user.exchange_accounts.exists?(exchange_account_id)` to avoid loading full list.

**Destroy behavior:** On `ExchangeAccount`, add `has_many :portfolios, dependent: :nullify` so destroying an account sets `portfolios.exchange_account_id` to nil instead of raising a FK error. Aligns with optional "All exchanges" semantics.

### Phase 2: IndexService and controller — exchange tab and date/exchange filters

- [x] `Trades::IndexService`: signature extend to `call(user:, view: nil, portfolio_id: nil, exchange_account_id: nil, from_date: nil, to_date: nil)`.
- [x] Normalize view: if `view.to_s == "portfolio"` then `"portfolio"`; elsif `view.to_s == "exchange"` and `exchange_account_id.present?` then `"exchange"`; else `"history"`. When view is `"exchange"`, resolve exchange account with `user.exchange_accounts.find_by(id: exchange_account_id)`; if not found, fall back to history or 404 (product choice: fallback to history).
- [x] `load_trades`: (1) **portfolio** — `portfolio.trades_in_range.includes(:exchange_account)` (unchanged call, scope now includes exchange when set). (2) **exchange** — `user.trades.where(exchange_account_id: exchange_account_id).includes(:exchange_account)`; then apply date filter: if `from_date` present, `where("executed_at >= ?", from_date.to_date.beginning_of_day)`; if `to_date` present, `where("executed_at <= ?", to_date.to_date.end_of_day)`. (3) **history** — `user.trades.includes(:exchange_account)`; apply `from_date`/`to_date` same way; if `exchange_account_id` present, `where(exchange_account_id: exchange_account_id)`.
- [x] Return from service: add `exchange_account:`, `exchange_accounts:` (user's list for tabs and History filter), `from_date:`, `to_date:` to the result hash.
- [x] `TradesController#index`: resolve exchange account with `current_user.exchange_accounts.find_by(id: params[:exchange_account_id])`; when view is "exchange" and param present but account not found, redirect to `trades_path(view: "history")` with flash. Pass `exchange_account&.id` (and from_date, to_date) into IndexService. Assign `@exchange_account`, `@exchange_accounts`, `@from_date`, `@to_date` from result. Keep default redirect to default portfolio when no view/portfolio_id.

**Files to change:** `app/services/trades/index_service.rb`, `app/controllers/trades_controller.rb`.

#### Research insights (Phase 2)

**IDOR prevention:** Never use raw `params[:exchange_account_id]` for loading data. In the controller, resolve once: `exchange_account = current_user.exchange_accounts.find_by(id: params[:exchange_account_id])`; pass `exchange_account&.id` to the service. The service receives only a pre-scoped id (or nil). Use `find_by` (not `find`) so "not found" can be handled by redirect instead of 404.

**Invalid exchange_account_id (exchange tab):** When view is "exchange" and the id is present but not in the user's accounts, redirect to `trades_path(view: "history")` with a flash (e.g. "That exchange account wasn't found."). Do not render 404 for list/filter flows—avoids leaking existence of the id. Clear the invalid param from the URL.

**Strong params:** Permit `exchange_account_id`, `from_date`, `to_date` for the index action (query params). Allow blank; use `.presence` when reading. No extra sanitization—`find_by(id: ...)` safely ignores non-integer values.

### Phase 3: Trades index UI — tabs and filters

- [x] **Tabs:** In `trades/index.html.erb`, nav: first link "History" to `trades_path(view: "history", **filter_params)`. Then iterate `@exchange_accounts` (from service): link label `account.provider_type.to_s.capitalize`, href `trades_path(view: "exchange", exchange_account_id: account.id, from_date: @from_date, to_date: @to_date)` (or pass a helper that builds params for current view). Last link "Portfolio" to `trades_path(view: "portfolio", portfolio_id: @portfolio&.id)`. Active class: History when `@view == "history"`; exchange when `@view == "exchange"` and `@exchange_account&.id == account.id`; Portfolio when `@view == "portfolio"`. If `@exchange_accounts` is nil (e.g. portfolio view only), load for tabs: pass `exchange_accounts` from service in all cases (e.g. always return user's exchange_accounts for the nav).
- [x] **History filters:** When `@view == "history"`, render a filter form (GET): from_date, to_date (date fields), exchange select (options: "All exchanges" + exchange_accounts). Hidden field `view` = history. Submit and links preserve params. Use a small helper or local vars for `filter_params` (view, from_date, to_date, exchange_account_id) so pagination and form action stay in sync.
- [x] **Exchange tab filters:** When `@view == "exchange"`, render filter form: from_date, to_date; hidden fields `view`, `exchange_account_id`. Submit preserves exchange tab and dates.
- [x] **Empty state:** When `@view == "exchange"` and `@positions.empty?`, show "No trades for this exchange." with optional link to sync or exchange accounts.
- [x] **Column modal:** Add hidden fields (or append to form action) for `view`, `exchange_account_id`, `from_date`, `to_date`, `portfolio_id` when present so that after "Save" the user remains on the same tab and filters.

**Files to change:** `app/views/trades/index.html.erb`, possibly `app/helpers/trades_helper.rb` for `filter_params` or similar.

#### Research insights (Phase 3)

**Single helper for filter state:** Define a permitted list (e.g. `TRADES_INDEX_PARAMS = %w[view from_date to_date exchange_account_id portfolio_id]`) and a helper `trades_index_filter_params(overrides = {})` that returns `params.permit(TRADES_INDEX_PARAMS).to_h.merge(overrides).delete_if { |_, v| v.blank? }`. Use it for: (1) filter form `url: trades_path(trades_index_filter_params)`, (2) tab links `trades_path(trades_index_filter_params.merge("view" => "exchange", "exchange_account_id" => account.id))`, (3) optional redirect after column-preference save.

**Column modal:** Include hidden fields for `view`, `portfolio_id`, `from_date`, `to_date`, `exchange_account_id` in the column-preference form. The action that handles the PATCH should redirect to `trades_path(params.permit(TRADES_INDEX_PARAMS).to_h.compact_blank)` so the URL after "Save" preserves tab and filters.

**Pagy:** For a GET index, Pagy uses the current request's GET params when building pagination links. No `pagy_url_for` override or params merge is required—view and filter params are preserved automatically. Only ensure the index action is GET and you are not replacing the request when calling `pagy`.

### Phase 4: Tests and edge cases

- [x] **Portfolio:** Test `trades_in_range` with `exchange_account_id` set returns only that account's trades in range; with nil returns all user trades in range. Test validation: setting `exchange_account_id` to another user's account fails.
- [x] **IndexService:** Test history with `from_date`/`to_date` and with `exchange_account_id`; test exchange view with date filter; test portfolio with exchange scoped (and without). Test exchange_account_id not in user's accounts: fallback to history or safe behavior.
- [x] **TradesController:** Test `view=exchange` with valid `exchange_account_id` (user's) returns 200; with another user's or invalid `exchange_account_id` redirects to history with flash (no 404 leak). Test filter params preserved in response.
- [x] **Dashboard:** Confirm existing dashboard spec or manual check that default portfolio summary uses `trades_in_range` (so exchange scope is respected once Phase 1 is done).

**Files to add/change:** `test/models/portfolio_test.rb`, `test/services/trades/index_service_test.rb` (or equivalent), `test/controllers/trades_controller_test.rb`.

---

## Technical Notes

- **Exchange account ownership:** Always scope `exchange_account_id` to `current_user.exchange_accounts` in controller and service; never trust param without lookup. Prefer `current_user.exchange_accounts.find_by(id: ...)` so "not found" is a single query and does not leak existence of the id (IDOR-safe).
- **Date params:** Use `from_date`/`to_date` as strings or date; coerce to date in service with `.to_date` and use `beginning_of_day`/`end_of_day` for range.
- **Pagy:** For GET index, Pagy includes existing query params in pagination links by default; no extra config needed. Use a single `trades_index_filter_params`-style helper for forms and links so the permitted set is consistent.
- **Column preference:** Persist context (view, exchange_account_id, from_date, to_date, portfolio_id) via hidden fields in the column modal form; the PATCH handler redirects to `trades_path(permitted_context_params)` so the URL after save keeps tab and filters.
- **Data integrity:** Migration should be reversible (`add_reference`/`remove_reference`). Optional FK `on_delete: :nullify` plus `ExchangeAccount has_many :portfolios, dependent: :nullify` keeps behavior consistent when an exchange account is deleted.

---

## Out of scope (follow-up)

- URL/state polish: default tab when user has one exchange (brainstorm: keep History as default).
- Dashboard explicit "per exchange" summary blocks.
- Multiple exchanges per portfolio (join table); v1 is single optional exchange only.
