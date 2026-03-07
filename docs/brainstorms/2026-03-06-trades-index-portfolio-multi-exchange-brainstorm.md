# Trades Index and Portfolio Multi-Exchange Rework — Brainstorm

**Date:** 2026-03-06  
**Scope:** Rework trades index view and portfolio to support multiple exchanges: per-exchange tabs, History filters, and optional exchange scope on portfolios.

---

## What We're Building

1. **History tab**
   - Add **filters**: date range and exchange(s). User can narrow to "Jan–Mar 2026" and/or "Binance only", "BingX only", or "All exchanges". Same positions table as today; filtering applies to the underlying trades.

2. **One tab per exchange**
   - **Dynamic tabs** from the user's linked exchange accounts: e.g. **History | Binance | BingX | Portfolio**. Each exchange tab shows only that account's trades (same positions table, same columns). No exchange selector inside the tab—the tab itself is the scope. **Date-range filter on each exchange tab** so the user can narrow to e.g. "Jan–Mar 2026" for that exchange.

3. **Portfolio: optional exchange scope**
   - **Current behavior:** Portfolio is a date window over all user trades; portfolio view shows both exchanges' trades mixed.
   - **Change:** When creating/editing a portfolio, user can optionally choose one exchange account ("Include trades from: All exchanges | Binance | BingX"). If set, the portfolio view shows only that account's trades within the portfolio's date range. If "All exchanges", behavior stays as today. Existing portfolios remain "all exchanges" until the user edits them.

4. **What else to consider**
   - **URL/state:** Filters and active tab should be reflected in the URL (e.g. `?view=history&exchange_id=…&from=…&to=…`) so links and refresh preserve state.
   - **Default tab:** When user has one linked account, "History" vs that exchange tab—decide whether to default to History or to the single exchange (or keep History as default).
   - **Empty state:** Exchange tab with no trades: show a clear "No trades for this exchange" (and optionally "Sync" link).
   - **Dashboard/summary:** If dashboard shows a default portfolio summary, respect that portfolio's exchange scope when computing P&L/balance.
   - **Column consistency:** Same configurable columns across History, each exchange tab, and Portfolio; no extra columns per exchange unless we add something like "Exchange" on History/Portfolio when showing multiple exchanges.

---

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Exchange tabs | One tab per linked exchange account (dynamic) | User said "one new tab per exchange"; clear mental model: one tab = one account's trades. |
| Portfolio exchange scope | Optional single exchange account; when set, filter trades to that account in the date range; null = all exchanges | Fixes "portfolio view showing both exchanges"; optional keeps existing portfolios working (v1: one exchange or all). |
| History filters | Date range + exchange(s) | Lets users narrow History without switching to an exchange tab or a portfolio. |
| Portfolio model change | Add optional single `exchange_account_id` (v1); null = all exchanges | Keeps v1 simple; "all" or one exchange per portfolio. Multiple exchanges per portfolio can be added later if needed. |

---

## Why This Approach

- **Per-exchange tabs** give a direct way to see "just Binance" or "just BingX" without extra dropdowns; tabs scale with the number of linked accounts.
- **History filters** keep a single "everything" view but allow ad-hoc narrowing by date and exchange; complements the exchange tabs.
- **Optional exchange on portfolio** keeps backward compatibility (existing portfolios = all exchanges), supports "Q1 2026 Binance only" or "Demo BingX", and fixes the issue where portfolio view currently mixes both exchanges.

---

## Approaches (High Level)

### Approach A — Minimal: Exchange tabs + portfolio exchange (recommended)

- **Trades index:** Tabs = History | [one tab per exchange account, e.g. Binance, BingX] | Portfolio. History = all trades, with new filters (date range, exchange multi-select). Exchange tab = that account's trades only. Portfolio = existing selector + portfolio's date range and optional exchange scope.
- **Portfolio:** Add optional single `exchange_account_id`. Form: "Include trades from: [All exchanges / Binance / BingX]". When set, `trades_in_range` scopes to that account; when null, all exchanges (current behavior).
- **Pros:** Solves both "one tab per exchange" and "portfolio showing both exchanges"; small, clear surface. **Cons:** Slightly more complex portfolio form and query.

### Approach B — Tabs + filters only, no portfolio exchange

- Same tabs and History filters as A. **Portfolio** unchanged: no exchange scope; portfolio view keeps showing all exchanges in the date range.
- **Pros:** No portfolio model change. **Cons:** Does not fix "portfolio view showing me both exchanges' trades"; user would need an exchange tab or History filter for per-exchange view.

### Approach C — Exchange tabs + portfolio exchange + URL/state polish

- Same as A, plus: filters and active tab in URL; default tab rule when one account; empty-state copy and dashboard respecting portfolio exchange scope.
- **Pros:** Better UX and shareable links. **Cons:** More work; can be phased after A.

**Recommendation:** **Approach A** (exchange tabs + History filters + optional exchange on portfolio). Add URL/state and dashboard/empty-state refinements (C) in a follow-up if needed.

---

## Resolved Questions

1. **Exchange tab meaning:** One new tab **per exchange** (per linked exchange account), not one "Exchange" tab with a dropdown.
2. **Portfolio current issue:** Portfolio view currently shows both exchanges' trades; we add optional exchange scope so a portfolio can show one or more exchanges (or all).
3. **Portfolio "covers" exchange:** Data model already links trades to `exchange_account`; we add an optional filter on portfolio so the *view* can be scoped to specific account(s).
4. **Multiple exchanges per portfolio (v1):** Single optional `exchange_account_id` on Portfolio; null = all exchanges. Multiple exchanges per portfolio can be added later if needed.
5. **Date filter on exchange tabs:** Each exchange tab has its own date-range filter (e.g. "Jan–Mar 2026" for that exchange).

---

## Open Questions

None. Ready for planning.

---

## Repository Context

- **Trades index:** `TradesController#index`, `Trades::IndexService`; view param `history` | `portfolio`; `portfolio_id` for portfolio selector. No exchange filtering today.
- **Portfolio:** `Portfolio` has `user_id`, `name`, `start_date`, `end_date`, `initial_balance`, `notes`, `default`. `trades_in_range` filters by date only (`user.trades` in range).
- **Trade:** `belongs_to :exchange_account`; user has many trades through exchange_accounts.
- **Exchange accounts:** `ExchangeAccount` has `provider_type` (e.g. binance, bingx); listed at `/exchange_accounts` (separate page). No tabs on Trades page yet for per-exchange view.
