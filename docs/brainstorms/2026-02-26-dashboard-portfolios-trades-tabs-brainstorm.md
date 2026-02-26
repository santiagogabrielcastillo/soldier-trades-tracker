# Dashboard, Portfolios, and Trades Tabs — Brainstorm

**Date:** 2026-02-26  
**Scope:** Post-MVP improvements: dashboard, sync rollback, trades view structure, named portfolios.

---

## What We're Building

1. **Rollback 6‑month lookback**  
   Sync uses `account.linked_at || account.created_at` again (no temporary 6‑month window). Document that BingX may expose limited history; 90‑day fallback in the client remains for empty long ranges.

2. **Trades view: tabs / separation**  
   - **History tab:** All trades ever (current table: positions, leverage, margin, net P&L, balance). No filtering by portfolio.  
   - **Portfolio tab(s):** View filtered by the selected named portfolio’s date range; balance from 0 for that range.

3. **Named portfolios (Option C)**  
   - User creates **portfolios** with a **name**, **start date**, **end date**, and optional **initial balance** (floor, e.g. $20).  
   - Each portfolio is a **date window** over the same underlying trades: only trades with `executed_at` in [start_date, end_date] are shown; **balance** = initial balance + running sum of realized P&L in that window.  
   - User can **set any portfolio as default**; app opens to the default portfolio’s view (or to History if no default).  
   - No separate “Current” entity—default is just the portfolio marked as default.

4. **Dashboard**  
   - Central place for: linked exchange accounts, last sync, and **default portfolio summary** (period P&L, balance, maybe trade count).  
   - Optional: quick link to “Trades” (History or default portfolio).

5. **Trader‑friendly extras (suggestions)**  
   - **Notes** on a portfolio (e.g. “Q1 2026 – LINK focus”).  
   - **Summary stats** per portfolio: period P&L, number of positions, win rate (optional).  
   - **Export:** CSV export for the current view (History or selected portfolio’s date range).  
   - **Dashboard:** Show default portfolio’s balance and period P&L at a glance.

---

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|------------|
| Portfolio model | Date range (start_date, end_date) + optional initial_balance | No trade duplication; same trades, filtered by time. initial_balance = floor (default 0) so balance = floor + P&L. |
| “Current” / default | One portfolio marked default per user | User picks which portfolio is “current”; no special built‑in “Current” entity. |
| Trades UI structure | Tabs: History \| Portfolio (with selector) | History = all; Portfolio = selected portfolio window; balance = initial_balance + running P&L. |
| Sync scope | Revert to linked_at (rollback 6‑month) | Align with “day 0” product intent; document API limits; keep 90‑day fallback for empty responses. |
| Balance in portfolio view | initial_balance + running P&L in window | User sets a floor (e.g. $20); balance = floor + cumulative realized P&L in that portfolio range. |

---

## Why This Approach

- **Portfolios as date windows:** No many‑to‑many trade↔portfolio; one source of truth (trades), filtered by portfolio dates. Easy to add “Q1 2026”, “Demo”, etc.  
- **Default portfolio:** One place to set “what I see first”; dashboard and Trades can both key off it.  
- **History tab:** Preserves full audit trail; portfolio view is for “this period” analysis.  
- **Notes + stats + export:** Low‑effort value for traders (notes, period P&L, CSV) without changing core model.

---

## Approaches (High Level)

### Approach 1 — Minimal: Portfolio + tabs, no dashboard change

- Add **Portfolio** model: `user_id`, `name`, `start_date`, `end_date`, `initial_balance` (decimal, default 0), `default` (boolean; only one true per user).  
- Trades index: **tabs** “History” | “Portfolio”. History = current behavior (all trades). Portfolio = dropdown to pick portfolio, then same table with trades filtered by portfolio’s date range and balance from 0.  
- Rollback sync to `linked_at`; keep 90‑day fallback.  
- **Pros:** Small surface area, clear behavior. **Cons:** Dashboard still minimal.

### Approach 2 — Portfolio + tabs + dashboard summary (recommended)

- Same as 1, plus **dashboard** shows: exchange accounts (existing) + **default portfolio summary** (name, date range, period P&L, balance, trade count). If no default portfolio, show “All time” or prompt to create one.  
- Optional: **notes** on Portfolio (text field).  
- **Pros:** Single place to see “how is my current period doing”; encourages use of default portfolio. **Cons:** Slightly more UI.

### Approach 3 — Portfolio + tabs + dashboard + export

- Same as 2, plus **Export** (e.g. “Download CSV”) on Trades for the current view (History = all trades; Portfolio = portfolio’s range).  
- **Pros:** Direct value for taxes/review. **Cons:** Extra endpoint and CSV handling.

**Recommendation:** Start with **Approach 2** (portfolios, tabs, dashboard summary, optional notes). Add export (Approach 3) in a follow‑up if needed.

---

## Resolved Questions

1. **Portfolio semantics:** Option C — only named portfolios; any can be set as default; each has start and end date.  
2. **Current portfolio:** “Current” = whichever portfolio is marked default; no separate “Current” entity.  
3. **Start/end date:** Each portfolio has start_date and end_date; trades in that range are included; balance = initial_balance + running P&L in that window.  
4. **End date optional:** Yes — end_date nullable; null means "from start_date to now" (open-ended; new trades included).  
5. **Overlapping portfolios:** Yes — overlapping date ranges allowed; each portfolio is a lens over the same data.  
6. **Dashboard when no default:** Show "All time" summary (all trades, total balance) in the portfolio summary area until user sets a default portfolio.  
7. **Initial balance (floor):** When creating/editing a portfolio, user can set an optional **initial balance** (e.g. $20). Balance in that portfolio's view = initial_balance + running sum of realized P&L in the date window. Default 0 if not set.

---

## Open Questions

None. Ready for planning.

---

## Repository Context

- Existing: User, ExchangeAccount, Trade, PositionSummary; sync job; trades index with positions and balance.  
- Layout: Dashboard (root), Exchange accounts, Trades, Settings.  
- No tabs or portfolio concept yet; sync currently has temporary 6‑month lookback to revert.
