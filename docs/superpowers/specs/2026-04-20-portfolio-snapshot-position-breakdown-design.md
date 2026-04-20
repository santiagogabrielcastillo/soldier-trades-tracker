# Portfolio Snapshot Position Breakdown

**Date:** 2026-04-20

## Overview

Extend the Stocks Performance tab to capture per-position allocation data (% and value) in each weekly, monthly, and manual portfolio snapshot. Add two UI elements: a stacked area chart showing allocation over time, and expandable snapshot rows revealing the per-position breakdown.

## Data Model

### Migration

Add `positions_data jsonb` column (nullable, default `[]`) to `stock_portfolio_snapshots`.

### Positions data shape

Each snapshot stores an array of position entries in native portfolio currency (USD or ARS):

```json
[
  { "ticker": "AAPL", "value": 12400.00, "pct_of_total": 42.3 },
  { "ticker": "MSFT", "value": 9800.00,  "pct_of_total": 33.5 },
  { "ticker": "CASH", "value": 7000.00,  "pct_of_total": 24.2 }
]
```

- `value`: market value of the position at snapshot time (shares × live price, or cash balance)
- `pct_of_total`: `value / total_value * 100`
- Cash is always included as a `"CASH"` entry when non-zero
- Old snapshots have `positions_data = []`; the UI degrades gracefully (no toggle, no chart point)

### Model changes

Add a `positions_breakdown` reader on `StockPortfolioSnapshot` that parses `positions_data` into an array of plain structs/hashes for view consumption.

## Service Changes

### `Stocks::PortfolioSnapshotService`

Currently calls `compute_portfolio_value` which fetches live prices and sums open positions. Extend this single pass to also build `positions_data`:

1. For each open position: `value = prices[ticker] * shares`
2. Append cash: `{ ticker: "CASH", value: cash_balance }`
3. Compute `pct_of_total` for each entry after summing total
4. Pass `positions_data` into the `create!` call alongside `total_value`

No extra API calls are needed — prices are already fetched. Both the manual "Record entry" flow and the automated `TakeSnapshotJob` (weekly/monthly) go through this service and gain breakdown capture automatically.

## UI — Performance Tab

### 1. Stacked area chart: "Allocation over time (%)"

- Rendered above the existing TWR chart
- Uses Chart.js via the existing `stocks-charts` Stimulus controller (`stocks_charts_controller.js`)
- Data passed as JSON in the controller's data value attribute, same pattern as TWR
- Each ticker (and CASH) is a dataset with a distinct color
- X-axis: snapshot dates; Y-axis: 0–100%
- Only snapshots with non-empty `positions_data` are plotted
- If fewer than 2 qualifying snapshots exist, shows an empty-state message matching the TWR chart style
- Percentage labels rendered permanently on the chart (not only on hover), if Chart.js `datalabels` plugin supports it without significant layout cost

### 3. Persistent % labels on existing allocation charts

Where feasible via Chart.js config, update existing percentage-based charts (e.g. the portfolio allocation pie chart on the Stocks index) to show % labels directly on the chart at all times rather than only on hover. Gated on whether the chart type and data density allow readable labels — skip for charts where labels would overlap.

### 2. Expandable snapshot rows

- Each snapshot row in the table gets a toggle chevron button (rightmost column)
- Clicking reveals an inline sub-table with: Ticker | Value | % of Total
- Rows sorted by `pct_of_total` descending
- Values formatted in portfolio currency (USD or ARS) matching existing formatters
- For snapshots with empty `positions_data`, the toggle button is hidden
- Implementation: `<details>/<summary>` HTML or a lightweight Stimulus toggle — no extra network requests; breakdown data is embedded in the page at render time

## Error Handling

- If price fetching partially fails during snapshot capture, positions without prices are omitted from `positions_data` (same behavior as current `compute_portfolio_value`)
- `positions_data` column is nullable; `[]` is the safe default for old records

## Out of Scope

- Querying across snapshots by ticker (e.g. "AAPL weight history" as a standalone query)
- Editing position breakdown after a snapshot is recorded
- Absolute-value view on the allocation chart (% only)
