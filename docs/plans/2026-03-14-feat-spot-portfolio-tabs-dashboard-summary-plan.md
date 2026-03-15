---
title: Spot portfolio tabs and dashboard spot summary
type: feat
status: completed
date: 2026-03-14
---

# Spot portfolio tabs and dashboard spot summary

## Enhancement Summary

**Deepened on:** 2026-03-14  
**Sections enhanced:** Proposed solution (tabs + dashboard), Technical considerations, Edge cases, Implementation notes  
**Research sources:** Pagy docs (query param preservation), WAI-ARIA tabs pattern, Rails date-range scope patterns, existing codebase (trades index).

### Key improvements

1. **Pagination + filters:** Pagy preserves GET params by default; use GET for filter form and no custom `pagy_url_for` needed. Documented URL length caveat for future (many filters).
2. **Tab accessibility:** Use `<nav aria-label="Tabs">` and link-based tabs (already in trades index); optional enhancement: `role="tablist"` and `aria-current="page"` on active link for clarity.
3. **Filter scopes:** Apply filters only when params present; use `where(executed_at: from..to)` (range) for dates to keep queries safe and readable.
4. **Token filter:** Restrict to existing tokens (e.g. from spot_account) for select options to avoid arbitrary input if using a dropdown; free text with presence check is acceptable.

### New considerations

- Optional redirect from `/spot` to `spot_path(view: 'portfolio')` keeps URLs explicit; current plan leaves `/spot` as portfolio view without param (simpler).
- Dashboard spot block: when no positions, prefer "No spot positions" + link over only zeros to encourage first-time setup.

---

## Overview

Add (1) a two-tab spot portfolio view (Portfolio | Transactions) with a filterable, paginated transactions list, and (2) a compact “Spot” summary block on the dashboard below “Performance over time”. Context and decisions come from the [2026-03-14 brainstorm](docs/brainstorms/2026-03-14-spot-portfolio-transactions-dashboard-brainstorm.md).

## Problem statement / motivation

- **Spot portfolio:** Users have no way to see the list of spot transactions that built their positions; they only see the aggregated portfolio table. Auditing and filtering by date, symbol, or side requires this list.
- **Dashboard:** The dashboard is futures-only. Users with spot data have no at-a-glance spot summary without visiting the spot page.

## Proposed solution

### 1. Spot portfolio — two tabs

- **Route:** Keep single `GET /spot`; add query param `view` with values `portfolio` (default) or `transactions`.
- **Tab 1 — Portfolio:** Unchanged. Current positions table, “New transaction” button, “Import CSV” form. When `view` is missing or `portfolio`, show this.
- **Tab 2 — Transactions:** Table of spot transactions: Date/time, Token, Side, Amount, Price (USD), Total value (USD). Order: newest first (`executed_at :desc`). Filters: date range (`from_date`, `to_date`), symbol (`token`), side (buy / sell / all). Pagination: 25 per page (Pagy, same as trades index).
- **UI:** Tab strip under “Spot portfolio” heading (same visual pattern as `app/views/trades/index.html.erb`: border-bottom tabs, one active). Tab links preserve current filter params; filter form submits GET and preserves `view=transactions`.

### 2. Dashboard — spot summary block

- **Placement:** New section below “Performance over time”, above “Exchange accounts”.
- **Content:** One card/section titled “Spot” with: Total spot value (sum of current position values), Unrealized PnL, Open positions count, and a “View spot portfolio” link to `/spot`.
- **Data source:** Default spot account (same as `SpotController#index`). Use `Spot::PositionStateService` and `Spot::CurrentPriceFetcher` to compute value and unrealized PnL. If user has no spot account or no open positions, show the section with zeros or “No spot positions” and still show the link.

### Research insights (tabs and dashboard)

**Pagination and filter params (Pagy):** Pagy uses the request's GET params when building pagination links, so no custom `pagy_url_for` or params merge is required—ensure the index action is GET and the filter form uses `method: :get`. URL length: GET has browser/server limits; with 4–5 filter params (view, from_date, to_date, token, side) there is no risk; if filters grow (e.g. many symbols), consider POST + session or other approaches later.

**Tab UX and accessibility:** URL-driven tabs (e.g. `view=portfolio` / `view=transactions`) are bookmarkable and back-button friendly. Use `<nav aria-label="Tabs">` so assistive tech identifies the landmark (matches `app/views/trades/index.html.erb`). Optionally set `aria-current="page"` on the active tab link for clarity. Link-based tabs avoid focus/keyboard complexity of ARIA tablist while staying accessible.

**Dashboard summary placement:** Placing Spot below "Performance over time" keeps the dashboard order: summary → charts → spot → exchange accounts. Same card styling (`rounded-lg border border-slate-200 bg-white p-6 shadow-sm`) keeps visual consistency.

## Technical considerations

- **Spot index branching:** `SpotController#index` will branch on `params[:view]`. When `view=transactions`: load `@spot_account.spot_transactions` with scopes for `from_date`, `to_date`, `token`, `side`; order `executed_at: :desc`; paginate with `pagy(:offset, relation, limit: 25)`. When `view=portfolio` or blank: keep existing logic (positions, current prices, tokens for select). Redirects: optional default redirect when `view` is blank (e.g. to `spot_path(view: 'portfolio')`) for consistency; or leave as-is so `/spot` shows portfolio without param.
- **Filter params:** Introduce a permitted list (e.g. `SPOT_INDEX_PARAMS = %w[view from_date to_date token side]`) and a helper `spot_index_filter_params(overrides = {})` in a spot helper, mirroring `TradesHelper#trades_index_filter_params` and `TRADES_INDEX_PARAMS` (`app/helpers/trades_helper.rb`).
- **Dashboard:** Extend `Dashboards::SummaryService` to compute spot summary (default spot account → positions → current prices → total value, unrealized PnL, count). Add keys to the returned hash (e.g. `spot_value`, `spot_unrealized_pl`, `spot_position_count`) and expose them on `@dashboard` in `DashboardsController#show`. View: one new `<section>` with same styling as “Period summary” / “Exchange accounts” (e.g. `rounded-lg border border-slate-200 bg-white p-6 shadow-sm`).
- **SpotTransaction scope:** Add a scope for “newest first” (e.g. `order(executed_at: :desc)`) or use inline `reorder(executed_at: :desc)` in the controller; the model currently has `ordered_by_executed_at` (asc) only.
- **Performance:** Transactions list is a single filtered/paginated query; dashboard adds one call to `PositionStateService` and one to `CurrentPriceFetcher` for the user’s default spot account (same as spot index). No N+1.

### Research insights (technical)

**Optional filter scopes (safe pattern):** Apply filters only when the param is present. For date range use a range to keep SQL safe and readable: `relation = relation.where(executed_at: from_date.to_date.beginning_of_day..to_date.to_date.end_of_day)` only when both `from_date` and `to_date` are present (or separate `>=` / `<=` when only one is set). For `token` and `side`, use `where(token: params[:token])` and `where(side: params[:side])` only when present; allow only permitted values (e.g. `side` in `%w[buy sell]`) to avoid injection. Mirror `TradesController` + `Trades::IndexService` pattern: controller permits params, service or controller builds relation with conditional scopes.

**SpotTransaction ordering:** Add a scope e.g. `scope :newest_first, -> { order(executed_at: :desc) }` so the intent is clear and reusable; alternatively use `reorder(executed_at: :desc)` in the controller. Keep `ordered_by_executed_at` (asc) for CSV/position logic.

**Helper and permitted params:** A single `SPOT_INDEX_PARAMS` constant and `spot_index_filter_params(overrides = {})` in `SpotHelper` keeps tab links and filter form in sync (same as `TradesHelper::TRADES_INDEX_PARAMS` and `trades_index_filter_params`). Use for: `spot_path(spot_index_filter_params.merge("view" => "transactions"))` and form `url: spot_path(spot_index_filter_params)` with a hidden `view` field when on the Transactions tab.

## Acceptance criteria

### Spot portfolio tabs

- [ ] Visiting `/spot` or `/spot?view=portfolio` shows the existing portfolio view (positions table, New transaction, Import CSV).
- [ ] Visiting `/spot?view=transactions` shows the transactions list: columns Date/time, Token, Side, Amount, Price (USD), Total value (USD); default order newest first.
- [ ] Tab strip shows “Portfolio” and “Transactions”; active tab matches current `view`; switching tabs preserves other query params (e.g. filters when on Transactions).
- [ ] Filter form on Transactions tab: From date, To date, Token (symbol), Side (All / Buy / Sell); submit via GET; results and pagination reflect filters.
- [ ] Pagination: 25 items per page; pagination links preserve `view` and filter params (same Pagy behavior as trades index).
- [ ] When there are no spot transactions, Transactions tab shows an empty state message (e.g. “No spot transactions yet.”) and no table.

### Dashboard spot summary

- [ ] Dashboard shows a “Spot” section below “Performance over time” and above “Exchange accounts”.
- [ ] Section displays: Total spot value (formatted as money), Unrealized PnL (formatted, green/red when non-zero), Open positions count, and a “View spot portfolio” link to `spot_path`.
- [ ] When user has no spot positions (or no default spot account): section still appears with value $0, unrealized PnL $0, count 0, and the link to spot.
- [ ] Values match the logic used on the spot portfolio page (same `PositionStateService` and `CurrentPriceFetcher`).

### General

- [ ] No new routes; only query param `view` and existing `GET /spot`.
- [ ] Existing spot flows (new transaction, CSV import, portfolio table) unchanged.

## Success metrics

- Users can audit spot activity via the Transactions tab without leaving the spot page.
- Users see spot summary on the dashboard without navigating to spot.
- Filter and pagination behavior is consistent with the trades index.

## Dependencies and risks

- **Dependencies:** Existing `SpotController`, `Spot::PositionStateService`, `Spot::CurrentPriceFetcher`, `SpotAccount.find_or_create_default_for`, Pagy, and dashboard summary pattern.
- **Risks:** Low. Changes are additive (new tab, new section). Empty states and “no spot account” are handled in the brainstorm (show block with zeros + link).

## References and research

### Internal

- **Brainstorm:** `docs/brainstorms/2026-03-14-spot-portfolio-transactions-dashboard-brainstorm.md` — key decisions (tabs, filters, placement, pagination).
- **Tabs and filters:** `app/views/trades/index.html.erb` (tab strip, filter forms, `trades_index_filter_params`), `app/helpers/trades_helper.rb` (`TRADES_INDEX_PARAMS`, `trades_index_filter_params`).
- **Spot controller and view:** `app/controllers/spot_controller.rb`, `app/views/spot/index.html.erb`.
- **Dashboard:** `app/controllers/dashboards_controller.rb`, `app/services/dashboards/summary_service.rb`, `app/views/dashboards/show.html.erb`.
- **Pagination:** `app/controllers/trades_controller.rb` (`pagy(:offset, result[:positions], limit: 25)`), `config/initializers/pagy.rb`, `app/views/trades/index.html.erb` (pagy nav).
- **Spot models and services:** `app/models/spot_transaction.rb` (scope `ordered_by_executed_at`), `app/services/spot/position_state_service.rb`, `Spot::CurrentPriceFetcher`.

### External references (deepen-plan)

- [Pagy: query params in request](https://github.com/ddnexus/pagy/issues/846) — Pagy preserves GET params in pagination links.
- [WAI-ARIA Tabs pattern](https://www.w3.org/WAI/ARIA/apg/patterns/tabs/) — Tablist/tab/tabpanel roles and keyboard behavior (link-based tabs avoid full tablist complexity).
- Rails date-range scopes: use `where(column: start..end)` for safe, readable range queries; apply only when params present.

### User flows (SpecFlow-style)

1. **View portfolio:** User goes to `/spot` → sees Portfolio tab active and positions table. Clicks “Transactions” → URL becomes `/spot?view=transactions`, sees transactions table (newest first). Clicks “Portfolio” → back to portfolio view.
2. **Filter transactions:** On Transactions tab, user sets From/To dates, token, side, submits → URL has params, table shows filtered results; pagination preserves params.
3. **Dashboard:** User opens dashboard → sees Period summary, Performance over time, then Spot section (value, unrealized PnL, count, link). Clicks “View spot portfolio” → lands on `/spot`.

### Edge cases

- No spot transactions: Transactions tab shows empty state; dashboard spot block shows zeros and link.
- No exchange accounts (no current prices): Unrealized PnL and value on dashboard can show “—” or zero per existing spot index behavior (CurrentPriceFetcher returns empty).
- Pagination on transactions: Page 2+ preserves `view` and all filter params (Pagy default for GET).

### Research insights (edge cases)

- **Empty token/side in form:** If user submits the filter form with token or side blank, treat as "all" (do not filter by that dimension); `spot_index_filter_params` already strips blank values, so the relation should apply only present filters.
- **Invalid date format:** If `from_date`/`to_date` are malformed, use `to_date` on the param and rescue or validate; invalid dates can be ignored (no filter) or show a flash. Prefer ignoring invalid dates for robustness (same as many index UIs).
- **Token filter input:** If the token filter is a free-text field, restrict in the controller to a known set (e.g. tokens that exist for the spot_account) when building the relation, or allow any string and use `where(token: params[:token])` (SQL-safe as a single value). If using a select, populate from `spot_account.spot_transactions.distinct.pluck(:token).sort` plus optional "All" so UX is clear.

## Implementation notes

- **Files to add:** Helper for spot index params (e.g. `app/helpers/spot_helper.rb` with `SPOT_INDEX_PARAMS` and `spot_index_filter_params`) if not inlining in controller.
- **Files to modify:** `app/controllers/spot_controller.rb` (branch on `view`, load transactions with filters and pagy), `app/views/spot/index.html.erb` (tabs, conditional portfolio vs transactions table + filter form, pagy nav), `app/services/dashboards/summary_service.rb` (spot summary), `app/views/dashboards/show.html.erb` (Spot section), `app/models/spot_transaction.rb` (optional scope for `order(executed_at: :desc)`).
- **Tests:** Controller specs for `SpotController#index` with `view=portfolio` vs `view=transactions`, filter params, and pagination; dashboard summary service spec for spot keys; feature/request tests for tab switching and dashboard spot block visibility.

### Research insights (implementation)

- **Pagy with relation:** Use `pagy(:offset, relation, limit: 25)` (or the same pattern as `TradesController`: the service can return a relation for transactions and the controller calls `pagy` on it). For arrays, `pagy(:offset, array, limit: 25)`; for ActiveRecord relation, `pagy(relation, limit: 25)` or `pagy(:offset, relation, limit: 25)` per Pagy docs—confirm which variant the app uses (e.g. `exchange_accounts_controller` and `portfolios_controller` use `pagy(:offset, relation, limit: 25)`).
- **Dashboard service:** Add a private method e.g. `spot_summary` that loads default spot account, runs `PositionStateService`, fetches current prices for open tokens, computes total value and unrealized PnL, and returns `{ spot_value:, spot_unrealized_pl:, spot_position_count: }`. Merge into the main hash; handle nil spot account or empty positions with zeros.
- **View partial (optional):** The Spot section on the dashboard can be a partial e.g. `_spot_summary.html.erb` for clarity, or inline in `show.html.erb` to match Period summary and Exchange accounts; either is fine.
