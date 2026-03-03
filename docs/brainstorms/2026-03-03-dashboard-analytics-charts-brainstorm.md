# Dashboard analytics and charts — Brainstorm

**Date:** 2026-03-03  
**Scope:** Add value for traders on the dashboard: performance vs portfolio start, consistency metrics (win rate, avg win/loss), and visual history (balance + cumulative P&L over time).

---

## What We're Building

1. **Performance at a glance (vs portfolio start)**  
   Keep current period P&L and balance. Add **total return %** since portfolio start: `(current_balance - initial_balance) / initial_balance * 100` when `initial_balance > 0`; show "—" or N/A when 0. For "All time" (no default portfolio), total return is N/A or omit.

2. **Habits and consistency**  
   - **Win rate** — % of closed positions with `net_pl > 0` (count wins / count closed positions).  
   - **Avg win** — Mean `net_pl` over winning closed positions (optional: in $ or % of margin).  
   - **Avg loss** — Mean `net_pl` over losing closed positions.  
   - **Trade count** — Number of closed positions in the period (already have position count; can clarify "closed" vs "all" if we show open too).  
   All derived from the same `PositionSummary` set the dashboard already loads (closed rows only for win/loss stats).

3. **Visual history**  
   Two charts (or one chart with two series):  
   - **Balance over time** — X = time (by close date), Y = running balance after each closed position. Use `close_at` and the summary’s `balance` for closed positions; optionally add a "today" point at current balance.  
   - **Cumulative P&L over time** — X = time, Y = cumulative realized P&L (e.g. `balance - initial_balance` for portfolio, or running sum of `net_pl`).  
   Data comes from the same positions list, sorted by `close_at` ascending for the time series. No new sync or trade schema.

---

## Why This Approach

- **Single source of data:** All metrics and chart series come from `PositionSummary.from_trades_with_balance(trades, initial_balance)` already used by `Dashboards::SummaryService`. No new tables or jobs.  
- **Portfolio-first:** Total return % and charts are meaningful when a default portfolio (with initial_balance and date range) is set; "All time" can show the same consistency stats and charts over full history.  
- **Trader-friendly and shareable:** Win rate and avg win/loss are standard; balance + P&L curves give quick visual feedback. Design for "traders in general" so it stays useful when you add more users later.

---

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|------------|
| Comparison baseline | Portfolio start (initial_balance → current balance) | User chose "start of portfolio"; total return % is one number that answers "how did I do since I started this portfolio?". |
| Consistency metrics | Win rate, avg win, avg loss, closed position count | Common and easy to compute from closed PositionSummary rows; no new schema. |
| Charts | Both balance over time and cumulative P&L over time | User chose "both" (two small charts or one with two series). |
| Data source | Same positions from SummaryService (or extended service) | Avoid duplicate loading; extend dashboard service or add a small analytics component that receives positions. |
| Open positions in stats | Exclude from win rate / avg win / avg loss | Only closed positions have realized P&L; count "closed" for trade count in consistency section. |

---

## Approaches

### Approach A — Extend SummaryService + inline chart data (recommended)

- **SummaryService** (or a thin **Dashboards::AnalyticsService** called from the controller) loads positions once and computes: `total_return_pct`, `win_rate`, `avg_win`, `avg_loss`, `closed_count`, and two chart series: `balance_series` and `cumulative_pl_series` (arrays of `{ date, value }` from closed positions sorted by `close_at` asc).
- Dashboard view gets one set of instance variables and renders: existing period summary block + new stats (return %, win rate, avg win, avg loss) + a charts section with two small charts (or one chart with two lines).
- Charts: use a lightweight JS chart library (e.g. Chart.js or ApexCharts) with data passed as JSON in the page or in a data attribute; no extra API unless you prefer to load chart data via fetch later.
- **Pros:** One place for all dashboard data; simple mental model; easy to test. **Cons:** Page payload grows with number of positions (bounded by TRADES_LIMIT).
- **Best for:** Shipping everything in one go with minimal moving parts.

### Approach B — Metrics first, charts in a follow-up

- Phase 1: Add total return %, win rate, avg win, avg loss, closed count to the dashboard (same data source as now). No charts.
- Phase 2: Add balance-over-time and cumulative-P&L charts using the same service + chart library.
- **Pros:** Faster first deliverable; validates metrics in the UI before investing in charts. **Cons:** Two phases to get full vision.
- **Best for:** If you want to ship numbers quickly and add visuals once the rest is stable.

### Approach C — Charts via separate endpoint

- Dashboard service returns only summary numbers. Chart data is requested by the browser from a dedicated endpoint (e.g. `GET /dashboards/chart_data?portfolio_id=...`) that returns JSON time series. Frontend draws charts with that JSON.
- **Pros:** Lighter initial page load; chart data can be cached or filtered independently. **Cons:** Extra request and endpoint; more code paths; still same underlying positions.
- **Best for:** If you expect very large position counts or want to lazy-load charts.

**Recommendation:** **Approach A** — extend the dashboard service to compute all metrics and chart series in one place and render them on the same page. Keeps implementation simple and matches current app size; you can split or add an endpoint later if needed.

---

## Resolved Questions

1. **Primary user:** Self now; design for "traders in general" for future sharing.  
2. **Value areas:** Performance at a glance, habits/consistency, visual history (not symbol/time breakdown as first priority).  
3. **Compare to:** Portfolio start — total return % since start.  
4. **Charts:** Both balance over time and cumulative P&L over time (two charts or one with two series).  
5. **Trade count in consistency:** Use closed position count (exclude open rows for win rate and avg win/loss).

---

## Open Questions

None. Ready for planning.

---

## Repository Context

- **Dashboard:** `DashboardsController#show`, `Dashboards::SummaryService`, `app/views/dashboards/show.html.erb`. Summary shows period P&L, balance, position count, link to trades; exchange accounts section below.
- **Data:** `PositionSummary.from_trades_with_balance(trades, initial_balance)` returns sorted summaries with `net_pl`, `balance`, `close_at`, `open?`. Win rate and avg win/loss use closed rows only (`open?` false). Chart series from closed rows by `close_at` asc: balance = summary.balance, cumulative_pl = balance - initial_balance (portfolio) or running sum of net_pl (all-time).
- **No new models or migrations required** for metrics or chart data.
