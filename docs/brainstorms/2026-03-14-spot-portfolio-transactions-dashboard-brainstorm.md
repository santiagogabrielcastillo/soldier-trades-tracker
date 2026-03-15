# Spot Portfolio & Dashboard Improvements — Brainstorm

**Date:** 2026-03-14  
**Scope:** (1) Two-tab spot portfolio view: Portfolio + Transactions list with filters. (2) Dashboard spot summary so spot is visible at a glance.

---

## What We're Building

### 1. Spot portfolio view — two tabs

- **Tab 1 — Portfolio:** Current view unchanged: positions table (token, avg buy price, current qty, current price, net value, unrealized PnL/ROI, status). Actions: New transaction, Import CSV.
- **Tab 2 — Transactions:** List of all spot transactions that built the portfolio.
  - **Order:** By `executed_at` (e.g. newest first by default; configurable if needed).
  - **Attributes:** Date/time, token, side (buy/sell), amount, price (USD), total value (USD). Optional: link to spot account if multiple later.
  - **Filters:** Date range (from / to), symbol (token), side (buy / sell / all). Same filter UX pattern as trades index (form with params, no JS required).
- Tabs implemented like the existing Trades index (History / Exchange / Portfolio): URL-driven, border-bottom tab strip, one active tab.

### 2. Dashboard — spot summary

The dashboard today is **futures-only** (period summary, charts, exchange accounts). We want a **spot summary** so users see spot at a glance without leaving the dashboard.

**Open design:** What should the spot summary emphasize? Options below.

---

## Spot portfolio tabs — approach

- **Single route** (e.g. `GET /spot`) with a **view** param: `view=portfolio` (default) or `view=transactions`.
- **SpotController#index** loads either:
  - **Portfolio:** existing logic (positions, current prices, tokens for select).
  - **Transactions:** `@spot_account.spot_transactions` with filters applied (date range, token, side), ordered (e.g. `order(executed_at: :desc)`), optionally paginated (e.g. Pagy, same as trades).
- **Filters for transactions:** Query params `from_date`, `to_date`, `token`, `side`. Reuse the same form-and-submit pattern as `trades#index` (no client-side framework).
- **UI:** Tab strip under the "Spot portfolio" heading; "Portfolio" and "Transactions" tabs; below, either the positions table or the transactions table + filter form.

**Why this approach:** Matches existing app patterns (trades index tabs + filters), minimal new concepts, easy to implement and maintain.

---

## Dashboard spot summary — approaches

Three concrete options for what to show on the dashboard.

### A: Single “Spot” summary block (compact)

- One section/card: “Spot” with 3–5 metrics in a row.
- **Metrics (suggested):** Total spot value (sum of current position values), Unrealized PnL, number of open positions, optional: “Last 30d” buy/sell count or volume.
- **Link:** “View spot portfolio” → `/spot`.
- **Placement:** Below "Performance over time", above "Exchange accounts".
- **Pros:** Small footprint, clear “spot exists and here’s the headline.”  
- **Cons:** No breakdown by token or time trend on the dashboard.

### B: Spot + futures split in period summary

- Keep current period summary section but **label or split** so it’s explicit that it’s “Futures” (or “Futures (portfolio)”).
- Add a **second row or second card** for “Spot” with the same kind of metrics (balance/value, unrealized PnL, position count).
- **Pros:** Direct comparison: futures vs spot in one glance.  
- **Cons:** Period summary gets busier; “balance” for spot may need careful wording (e.g. “Spot value” vs “Balance” for futures).

### C: Spot-only when no futures (or minimal spot block always)

- If user has no exchange accounts / no futures data: show a prominent “Spot portfolio” card (value, unrealized PnL, link).
- If user has both: show a small “Spot” line or block (like A) so spot isn’t hidden.
- **Pros:** Surfaces spot for CSV-only users; doesn’t overwhelm futures-first users.  
- **Cons:** Two different dashboard layouts depending on data; slightly more branching in view/service.

**Recommendation:** **A (single compact Spot block)**. It’s simple, consistent for all users, and leaves room to add “Futures vs Spot” split later (B) if needed. YAGNI: start with one clear spot block and a link to the full spot page.

---

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Spot portfolio structure | Two tabs: Portfolio (current) + Transactions | User request; transactions list supports audit and filters without leaving the page. |
| Transactions list order | Newest first (`executed_at :desc`) | Confirmed: recent activity first. |
| Transactions filters | Date range, symbol (token), side | User-specified; sufficient for finding and auditing trades. |
| Tab implementation | URL param `view=portfolio` \| `view=transactions` | Same pattern as trades index; bookmarkable, no extra routes. |
| Dashboard spot summary shape | Single compact "Spot" block (approach A) | Low clutter, one place for spot; can evolve to B later. |
| Dashboard spot data source | Default spot account (same as spot#index) | One source of truth; consistent with current "one default spot account" MVP. |
| Dashboard spot block placement | Below "Performance over time", above "Exchange accounts" | User preference. |
| Transactions pagination | Same as trades index (e.g. 25 per page) | Consistent UX. |



## Open Questions

_None._

---

## Resolved Questions

- **Dashboard spot block placement:** Below "Performance over time", above "Exchange accounts".
- **Transactions default order:** Newest first (`executed_at :desc`).
- **Pagination for transactions list:** Same as trades index (e.g. 25 per page).

---

## Summary

- **Spot portfolio:** Add a second tab “Transactions” alongside “Portfolio”. Transactions: table (date, token, side, amount, price, total USD), filters (date range, symbol, side), ordered by time (newest first unless we decide otherwise).
- **Dashboard:** Add a compact “Spot” summary block (total value, unrealized PnL, open positions count, link to spot portfolio) below "Performance over time".
- **Transactions list:** Paginated like trades (e.g. 25 per page).

Next: Run `/plan` to implement.
