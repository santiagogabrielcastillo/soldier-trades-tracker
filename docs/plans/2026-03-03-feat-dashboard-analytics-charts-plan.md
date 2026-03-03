# feat: Dashboard analytics and charts (Approach A)

---
title: Dashboard analytics and charts (Approach A)
type: feat
status: completed
date: 2026-03-03
source_brainstorm: docs/brainstorms/2026-03-03-dashboard-analytics-charts-brainstorm.md
---

## Enhancement Summary

**Deepened on:** 2026-03-03  
**Sections enhanced:** Proposed Solution, Technical Considerations, Implementation outline, Dependencies & Risks  
**Research sources:** Chart.js + Rails importmap (SO, JSPM CDN), Chart.js 4 time/date axis, trading dashboard UX (win rate / avg win-loss conventions).

### Key improvements

1. **Chart.js + importmap** — Pin Chart.js to JSPM CDN in `config/importmap.rb` (not vendor download) to avoid breaking other Stimulus controllers. Register `Chart.register(...registerables)` inside the chart controller.
2. **Time axis** — Chart.js 4 time scale requires a date adapter (e.g. `chartjs-adapter-date-fns` + `date-fns`). Simpler alternative: use **category** scale with date strings as labels (no adapter), or document adapter pins if time scale is preferred.
3. **Trading dashboard UX** — Headline metrics (return %, win rate, avg win/loss) at top; charts below. Use green/red for P&L and positive/negative; keep consistency block scannable (same pattern as existing period summary).
4. **Empty state** — Charts must handle empty series without JS errors: check `series.length === 0` and show a message or placeholder; do not call `new Chart()` with empty data if the library errors.

### New considerations

- **Importmap pin method:** `bin/importmap pin chart.js` can add vendor files that break Stimulus; prefer explicit JSPM CDN pins in `config/importmap.rb` for Chart.js and `@kurkle/color`.
- **Date adapter (optional):** If you want true time-scale x-axis (zooming, nice tick spacing), add `chartjs-adapter-date-fns` and `date-fns` via importmap; otherwise category scale with formatted date labels is sufficient and keeps dependencies minimal.

---

## Overview

Add trader value to the dashboard: (1) performance vs portfolio start (total return %), (2) consistency metrics (win rate, avg win, avg loss, closed count), and (3) two time-series charts (balance over time, cumulative P&L over time). All data is derived from the same `PositionSummary` set already loaded by `Dashboards::SummaryService`; no new models or migrations. Approach A: extend the dashboard service to compute metrics and chart series in one place and render them on the same page with a lightweight JS chart library.

## Problem Statement / Motivation

- The dashboard currently shows only period P&L, balance, and position count. Traders want to see how they are doing since portfolio start, their win rate and average win/loss, and a visual curve of balance and P&L over time.
- Design is for "traders in general" so the product remains useful when shared with other users later.

## Proposed Solution

1. **Extend `Dashboards::SummaryService`** (or add a thin analytics component it calls) to compute from the existing `positions` array:
   - **Total return %** — `(summary_balance - initial_balance) / initial_balance * 100` when `initial_balance > 0`; `nil` for "All time" or when initial_balance is 0.
   - **Win rate** — % of closed positions with `net_pl > 0` (wins / closed_count). Use closed positions only (`open?` false).
   - **Avg win** — Mean `net_pl` over closed positions where `net_pl > 0`; `nil` if no winners.
   - **Avg loss** — Mean `net_pl` over closed positions where `net_pl < 0`; `nil` if no losers.
   - **Closed count** — Number of closed positions (for consistency section label/clarity).
   - **Chart series** — From closed positions sorted by `close_at` asc: `balance_series` = `[{ date: iso8601, value: balance }, ...]`, `cumulative_pl_series` = `[{ date: iso8601, value: balance - initial_balance }]` (portfolio) or running sum of `net_pl` (all-time). Optionally append a "today" point with current balance for balance series.

2. **Controller** — Pass new keys from the service result to instance variables: `@summary_total_return_pct`, `@summary_win_rate`, `@summary_avg_win`, `@summary_avg_loss`, `@summary_closed_count`, `@chart_balance_series`, `@chart_cumulative_pl_series` (or a single `@chart_data` hash with both series for the view).

3. **View** — In the period summary section: add Total return % (show "—" when nil). Add a "Consistency" subsection or row: Win rate, Avg win, Avg loss, Closed count (reuse `format_money` for dollar amounts; win rate as "X%"). Add a "Performance over time" section with two small charts (or one chart with two lines): Balance over time and Cumulative P&L over time. Data passed as JSON in a `data-` attribute or a `<script type="application/json">` tag for the chart library to consume.

4. **Charts** — Use a lightweight JS chart library (e.g. Chart.js) via importmap. One Stimulus controller (e.g. `dashboard_charts_controller.js`) that reads the data attribute and renders two line charts (or one chart with two datasets). No separate API endpoint.

## Technical Considerations

- **Positions order:** `from_trades_with_balance` returns summaries sorted open first then by recent activity. For chart series we need closed positions only, sorted by `close_at` asc. Filter `positions.reject(&:open?)` and sort by `close_at` in the service.
- **Edge cases:** No closed positions → win rate, avg win, avg loss show "—" or 0%; empty balance_series/cumulative_pl_series → render empty state or "No closed positions yet" in chart area. initial_balance 0 → total return % nil (show "—").
- **All-time view:** When `default_portfolio` is nil, `initial_balance` is 0; total return % is omitted or "—". Cumulative P&L series = running sum of `net_pl` in close_at order (starts at 0).
- **Performance:** Single query and single in-memory computation; payload size bounded by `PositionSummary::TRADES_LIMIT`. Acceptable for Approach A.
- **Chart library:** Chart.js is widely used and works with importmap (pin from CDN or vendor). Alternative: ApexCharts. Choose one and add to `config/importmap.rb` and a Stimulus controller.

### Research insights (Technical)

**Chart.js with Rails importmap**

- Pinning with `bin/importmap pin chart.js` downloads to `vendor/javascript/` and can break other Stimulus controllers (reported Rails 8 + Chart.js). **Fix:** Pin directly to JSPM CDN in `config/importmap.rb`, e.g. `pin "chart.js", to: "https://ga.jspm.io/npm:chart.js@4.5.1/dist/chart.js"` and same for `@kurkle/color`.
- In the Stimulus chart controller, use `Chart.register(...registerables)` before creating charts (required in Chart.js 4).

**Time scale vs category scale**

- Chart.js 4 time scale requires an external **date adapter** (e.g. `chartjs-adapter-date-fns` + `date-fns`). Without it, time scale throws "This method is not implemented".
- **Simpler option:** Use **category** scale with x-axis labels = array of formatted date strings (e.g. from `close_at.strftime("%b %d")`). No extra adapter; sufficient for balance/P&L over time. Use time scale only if you need zoom/pan or automatic tick spacing.

**Trading dashboard conventions**

- Win rate, average win, average loss, and closed count align with common trading analytics (Tradervue, PnL Ledger, backtesting dashboards). Optional future metrics: profit factor (gross profit / gross loss), expectancy per trade.
- UX: Put headline metrics (return %, win rate, avg win/loss) at top; charts in a "Performance over time" section below. Green for profit, red for loss (match existing `text-emerald-600` / `text-red-600`).

## Acceptance Criteria

- [x] **Total return %** — When default portfolio has `initial_balance > 0`, dashboard shows "Total return" with percentage `(current_balance - initial_balance) / initial_balance * 100` (e.g. "12.5%"). When initial_balance is 0 or "All time", show "—".
- [x] **Consistency block** — Dashboard shows Win rate (%), Avg win ($), Avg loss ($), Closed positions (count). All derived from closed positions only. When there are no closed positions, show "—" or "0" as appropriate.
- [x] **Balance over time chart** — A line chart with X = date (close_at), Y = balance after each closed position. Data from same positions, closed only, sorted by close_at asc. Optional: add current balance as final point.
- [x] **Cumulative P&L over time chart** — A line chart with X = date, Y = cumulative realized P&L (portfolio: balance - initial_balance; all-time: running sum of net_pl).
- [x] **No new endpoints or migrations** — All data from extended SummaryService (or equivalent); chart data inline in page.
- [x] **Empty states** — When there are no closed positions, consistency metrics show "—" or "0%" and charts show empty state or "No closed positions yet"; no JS errors.
- [x] **Tests** — Unit test(s) for the analytics computation (total return %, win rate, avg win, avg loss, chart series shape) given a set of positions; optionally a request test that dashboard renders and includes the new elements (or at least 200).

## Success Metrics

- Traders see at a glance: am I up since start (return %), and how consistent am I (win rate, avg win/loss).
- Visual history (two charts) provides quick feedback without opening the trades table.

## Dependencies & Risks

- **Dependencies:** Existing `PositionSummary`, `Dashboards::SummaryService`, `format_money` helper. New: chart library (Chart.js or similar) via importmap, one Stimulus controller for charts.
- **Risks:** (1) Chart library size/load — pick a small option or lazy-load if needed. (2) Empty state — zero closed positions must not break charts (empty array → no lines or message).

### Research insights (Risks)

- **Importmap + Chart.js:** Vendor-pinned Chart.js can break other Stimulus controllers; use JSPM CDN pins to avoid that risk.
- **Empty series:** Chart.js may throw or render incorrectly with empty data; controller must check `series.length` and render an empty-state message instead of instantiating the chart.

## Implementation outline

1. **Service layer** — In `app/services/dashboards/summary_service.rb`: after building `positions`, compute `summary_total_return_pct` (only when portfolio and initial_balance > 0), `summary_win_rate`, `summary_avg_win`, `summary_avg_loss`, `summary_closed_count` from closed positions; build `chart_balance_series` and `chart_cumulative_pl_series` (array of `{ date: s.close_at.iso8601, value: ... }`) from closed positions sorted by `close_at` asc. Add these keys to the returned hash. Keep a single load of trades/positions.
2. **Controller** — In `app/controllers/dashboards_controller.rb`: assign `@summary_total_return_pct`, `@summary_win_rate`, `@summary_avg_win`, `@summary_avg_loss`, `@summary_closed_count`, `@chart_balance_series`, `@chart_cumulative_pl_series` from result.
3. **View** — In `app/views/dashboards/show.html.erb`: add Total return % in period summary; add Consistency subsection (win rate, avg win, avg loss, closed count); add "Performance over time" section with a container for charts and a data attribute containing JSON for both series (e.g. `data-dashboard-charts-value` with value as JSON string).
4. **Charts** — Pin Chart.js in `config/importmap.rb` **to JSPM CDN** (not vendor): e.g. `pin "chart.js", to: "https://ga.jspm.io/npm:chart.js@4.5.1/dist/chart.js"` and `pin "@kurkle/color", to: "https://ga.jspm.io/npm:@kurkle/color@0.3.4/dist/color.esm.js"`. Create `app/javascript/controllers/dashboard_charts_controller.js` (Stimulus): in `connect()`, call `Chart.register(...registerables)`; read chart data from a data attribute (e.g. `this.element.dataset.chartValue`); if series are empty, show a "No closed positions yet" message and return (do not instantiate Chart). Use **category** scale for x-axis with labels = date strings from the series (no date adapter). Two canvas targets or one chart with two datasets (balance, cumulative P&L). Options: `responsive: true`, maintainAspectRatio if needed. Style colors to match (e.g. emerald for positive, red for negative).
5. **Tests** — Add unit tests for dashboard analytics: e.g. a test that given an array of PositionSummary (some open, some closed with known net_pl), the computed win rate, avg_win, avg_loss, and series lengths are correct. Add a test that total_return_pct is nil when initial_balance is 0. Optionally: request test `get dashboard_path` and assert response includes "Total return" or "Win rate" and 200.

### Research insights (Implementation)

**Chart controller pattern**

- Parse JSON from `data-dashboard-charts-value` (or similar); structure e.g. `{ balanceSeries: [{ date, value }], cumulativePlSeries: [{ date, value }] }`. Map to Chart.js format: labels = `series.map(d => d.date)` (or formatted), datasets[0].data = balance values, datasets[1].data = cumulative P&L values.
- Guard: `if (!balanceSeries?.length && !cumulativePlSeries?.length) { show empty state; return; }` to avoid calling `new Chart()` with no data if it throws.

**References**

- Rails importmap + Chart.js: [Stack Overflow](https://stackoverflow.com/questions/79818170/rails-8-importmap-and-chart-js) (use JSPM CDN).
- Chart.js 4 time scale: [Chart.js docs](https://www.chartjs.org/docs/next/axes/cartesian/time.html) (date adapter required); category scale avoids adapter.

## References & Research

- Brainstorm: `docs/brainstorms/2026-03-03-dashboard-analytics-charts-brainstorm.md`
- Existing dashboard: `app/controllers/dashboards_controller.rb`, `app/services/dashboards/summary_service.rb`, `app/views/dashboards/show.html.erb`
- PositionSummary: `app/models/position_summary.rb` (`open?`, `net_pl`, `balance`, `close_at`, `assign_balance!`)
- Helpers: `app/helpers/application_helper.rb` (`format_money`)
- Frontend: `config/importmap.rb`, `app/javascript/controllers/` (Stimulus)
