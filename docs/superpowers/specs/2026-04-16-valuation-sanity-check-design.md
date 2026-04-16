---
date: 2026-04-16
topic: valuation-sanity-check
---

# Valuation Sanity Check

## What We're Building

A standalone stock valuation tool at `GET /stocks/valuation_check` that answers: "if the price stays flat and earnings grow as expected, how cheap does this stock get over time?" The user enters a current price, forward EPS, and annual growth rate; the tool projects EPS and P/E for years 1–5 with color-coded cells to signal when the stock becomes attractive.

Accessible from the valuations and watchlist tabs via a "Sanity Check" link per row. When navigated to with a `?ticker=AMD` param, inputs are pre-filled from `StockFundamental` + current price. All projection math runs client-side — no server round-trip after page load.

## Architecture

- **Route:** `GET /stocks/valuation_check` (query param: `ticker`)
- **Controller:** `Stocks::ValuationCheckController#show` — thin, loads fundamentals and current price, passes to view
- **View:** `app/views/stocks/valuation_check/show.html.erb`
- **Stimulus:** `valuation_check_controller.js` — owns all calc and table rendering

## Data Flow

1. Controller looks up `StockFundamental.find_by(ticker:)` for the user's ticker
2. Fetches current price via `Stocks::CurrentPriceFetcher`
3. Derives `fwd_eps = price / fwd_pe` if both are present; otherwise nil
4. View renders pre-filled (or blank) inputs and an empty table skeleton
5. Stimulus recalculates on every `input` event: `eps_n = fwd_eps * (1 + growth/100)^n`, `pe_n = price / eps_n`

## UI

**Breadcrumb:** `Stocks → Valuation Check (TICKER)` using `BreadcrumbComponent`

**Inputs (editable):**
- Current price
- Forward EPS
- Annual growth rate (%)

**Projection table — columns:** Year | EPS | P/E at current price

**P/E color thresholds (fixed):**
- > 30 → red (expensive)
- 15–30 → yellow (fair)
- < 15 → green (attractive)
- < 10 → bright green (gift)

**Entry points:** "Sanity Check" link on each row in the valuations tab and watchlist tab, linking to `stocks_valuation_check_path(ticker: ticker)`.

## Error Handling

- No fundamental data → inputs render blank; user fills manually
- Invalid inputs (zero, negative, or blank price/EPS) → Stimulus shows "Enter valid inputs" instead of the table
- Growth rate of 0% → valid; flat EPS, constant P/E shown
- Ticker with no fundamentals → still works, just no pre-fill

## Open Questions

None.
