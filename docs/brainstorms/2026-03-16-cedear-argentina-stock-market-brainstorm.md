# Brainstorm: CEDEAR / Argentina Stock Market Support

**Date:** 2026-03-16
**Status:** Draft

---

## What We're Building

A **per-portfolio market mode** for stock tracking that supports the Argentine market alongside the existing US mode. In Argentina, retail investors buy **CEDEARs** — locally-traded certificates that represent a fractional interest in a US-listed stock (e.g. 10 AAPL CEDEARs ≈ 1 AAPL share). Prices are quoted in **ARS**, and converting to USD requires the **MEP (Dolar Bolsa) exchange rate**.

The feature adds:
1. A `market` flag on `StockPortfolio` (`:us` or `:argentina`)
2. A CEDEAR instrument registry holding ticker ↔ ratio mappings
3. A new price fetcher using **IOL (Invertir Online)** for ARS prices
4. A **MEP rate fetcher** to convert ARS → USD
5. A dual-currency P&L view showing **ARS** and **USD** side by side

This is **stocks-only** — crypto is not affected.

---

## Why This Approach

We extend the existing `StockPortfolio` / `StockTrade` models with a mode flag rather than creating a parallel model hierarchy. This is the minimal change that fits the established pattern (`SpotAccount`, `Portfolio`, and `StockPortfolio` all share the same `default`-flag + `find_or_create_default_for` structure). A separate `CedearPortfolio` model would duplicate all of that boilerplate for no gain.

---

## Key Decisions

| Decision | Choice | Rationale |
|---|---|---|
| **Setting scope** | Per `StockPortfolio` | Allows running a US and an Argentina portfolio in parallel |
| **Display currency** | Both ARS and USD side by side | User wants full picture |
| **Unit of tracking** | CEDEAR units (what the broker shows) | App handles ratio internally |
| **ARS → USD rate** | MEP / Dolar Bolsa | Standard reference for Argentine stock market investors |
| **Current CEDEAR prices** | IOL (Invertir Online) API | User's preferred source |
| **Ratio storage** | `CedearInstrument` table (ticker → ratio) | One source of truth; entered once, reused across trades |

---

## Data Model

### `StockPortfolio` — new column

```ruby
t.string :market, default: "us", null: false  # "us" | "argentina"
```

### New table: `cedear_instruments`

Stores the CEDEAR ticker, its ratio to the underlying US stock, and optionally the underlying ticker for reference.

```ruby
create_table :cedear_instruments do |t|
  t.string :ticker, null: false       # e.g. "AAPL"  (CEDEAR ticker as traded on BCBA)
  t.decimal :ratio, precision: 10, scale: 4, null: false  # e.g. 10.0 means 10 CEDEARs = 1 share
  t.string :underlying_ticker        # e.g. "AAPL" on NASDAQ (often same, sometimes different)
  t.timestamps
  t.index :ticker, unique: true
end
```

Ratios are **entered by the user** (or seeded from a curated list). They rarely change.

### `StockTrade` — no new columns needed

Trades continue to store `ticker`, `shares` (CEDEAR units), and `price_usd`. For Argentina-mode portfolios, `price_usd` stores the ARS price **at trade time** (the column is repurposed / re-labelled in the UI as "Price (ARS)").

> **Alternative considered:** add `price_ars` and keep `price_usd` for USD. Rejected for MVP — it doubles the price columns and requires a migration. The view layer can label the column correctly based on portfolio mode.

---

## Services

### `Stocks::IolClient`

Fetches current CEDEAR prices in ARS from the IOL public API.

```ruby
# GET https://api.invertironline.com/api/v2/portafolio/argentina/cotizaciones
# Returns: [{ simbolo: "AAPL", ultimo: 12500.0, ... }]
class Stocks::IolClient
  BASE_URL = "https://api.invertironline.com/api/v2"

  def quote(ticker)
    # GET /portafolio/argentina/cotizaciones?simbolo=TICKER
    # Returns price in ARS
  end
end
```

> **Open question:** IOL may require authentication. Need to confirm if there's a public unauthenticated endpoint or if an API key is needed.

### `Stocks::ArgentineCurrentPriceFetcher`

Mirrors `Stocks::CurrentPriceFetcher` interface but calls `IolClient`. Returns `Hash<ticker, BigDecimal>` where values are ARS prices.

### `Stocks::MepRateFetcher`

Fetches the current MEP (Dolar Bolsa) rate in ARS/USD.

```ruby
# Possible sources:
# - dolarapi.com (GET /v1/cotizaciones/bolsa) — free, no auth
# - bluelytics.com.ar/api/v2/latest — includes mep field
class Stocks::MepRateFetcher
  def self.call
    # Returns BigDecimal (e.g. 1150.0 ARS per USD)
  end
end
```

---

## P&L Calculation Changes

### `Stocks::PositionStateService`

No changes needed to the core FIFO algorithm. It remains currency-agnostic — it processes `price_usd` (which for Argentina mode is actually ARS).

The result is: `breakeven` and `realized_pnl` are in **ARS** for Argentina-mode portfolios.

### In the controller / view

```ruby
if portfolio.argentina?
  mep_rate = Stocks::MepRateFetcher.call        # ARS per USD
  current_prices_ars = Stocks::ArgentineCurrentPriceFetcher.call(tickers)

  positions.each do |pos|
    current_ars = current_prices_ars[pos.ticker]
    ratio = CedearInstrument.find_by(ticker: pos.ticker)&.ratio || 1

    unrealized_ars = (current_ars - pos.breakeven) * pos.shares
    unrealized_usd = unrealized_ars / mep_rate

    # USD equivalent of portfolio value
    value_usd = (current_ars * pos.shares) / (mep_rate * ratio)
  end
else
  # existing US flow (Finnhub)
end
```

---

## UI Changes

### Portfolio settings

Add a `Market` field to the `StockPortfolio` form:
- Radio: **US Market** / **Argentina (CEDEARs)**

### Stocks index — Argentina mode

- Price column header: "Price (ARS)" instead of "Price (USD)"
- Add a "MEP Rate" display badge (e.g. "MEP: $1,150 ARS/USD")
- P&L column: show ARS value + USD equivalent in muted text below
- Portfolio value summary: show both ARS total and USD equivalent

### CEDEAR Instrument management

Simple admin/settings page (or inline on the stocks page) to manage the `cedear_instruments` list:
- Ticker + Ratio + Underlying
- Could be pre-seeded with the 20–30 most common CEDEARs

---

## Open Questions

_(none — all questions resolved)_

---

## Resolved Questions

- **Setting scope:** Per portfolio (not global, not per-trade)
- **Display:** Both ARS and USD side by side
- **Units:** CEDEAR units (broker-native), ratio handled by the app
- **Exchange rate:** MEP / Dolar Bolsa
- **Price source:** IOL (Invertir Online)
- **IOL auth:** Requires API key — store in Rails credentials (same pattern as Finnhub)
- **Ratio versioning:** Single current value per ticker; user updates manually on corporate actions
- **Trade entry UX:** Form auto-fills ratio from `cedear_instruments` table; user can override
- **MEP rate source:** `dolarapi.com` (`GET /v1/cotizaciones/bolsa`) — free, no auth required
