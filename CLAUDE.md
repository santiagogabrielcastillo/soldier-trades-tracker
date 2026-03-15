# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
# Development server (Rails + Tailwind watcher)
./bin/dev

# Tests
bin/rails test                                    # all tests
bin/rails test test/path/to_test.rb              # single file
bin/rails test:system                            # system tests (Capybara/Selenium)

# Linting
bundle exec rubocop              # check
bundle exec rubocop -a           # auto-fix

# Database
bin/rails db:create db:migrate
```

## Architecture

**Purpose:** Crypto futures trading portfolio tracker. Syncs trades from Binance and BingX exchanges, aggregates them into positions, and computes P&L/ROI metrics.

### Key Data Flow

1. `SyncDispatcherJob` runs on a schedule, checks each user's `sync_interval`, and enqueues `SyncExchangeAccountJob` for accounts that are due (max 2 syncs/day per account).
2. `SyncExchangeAccountJob` calls `ExchangeAccounts::SyncService`, which fetches raw trades from the exchange client and calls `Positions::RebuildForAccountService`.
3. `Positions::RebuildForAccountService` uses `PositionSummary` (a non-persisted model) to convert raw trades into `Position` records — including BOTH-chain splitting for Binance one-way mode.
4. The dashboard (`Dashboards::SummaryService`) reads positions and fetches current prices to display unrealized P&L.

### Exchange Clients (`app/services/exchanges/`)

Each exchange follows a `BaseProvider` pattern:
- `BinanceClient` / `BingXClient` — fetch raw trades from exchange APIs
- `Binance::TradeNormalizer` / `BingX::TradeNormalizer` — convert to a unified internal format
- Two normalization styles: **trade-style** (price + qty → fee/net_amount computed by `Exchanges::FinancialCalculator`) and **income-style** (fee + net_amount taken directly from exchange)
- Deduplication by `symbol + executed_at + side + net_amount` to handle overlapping API endpoints

### Position Calculation (`PositionSummary`)

`PositionSummary` is a non-persisted model (no DB table) holding the core financial logic:
- Splits BOTH-chain trades (Binance one-way mode) by detecting running quantity sign-flips
- Aggregates multiple closing legs into one closed position row
- Computes `entry_price`, `exit_price`, `leverage`, `margin_used`, `net_pl`, `roi_percent`
- Unrealized P&L: `(current_price - entry) * qty` for longs, `(entry - current) * qty` for shorts

### Models & Relationships

- **User** → many `ExchangeAccount`, `Trade`, `Portfolio`, `SpotAccount`
- **ExchangeAccount** → many `Trade`, `SyncRun`; holds encrypted `api_key`/`api_secret` (Rails 7.2 encryption)
- **Trade** → belongs to `ExchangeAccount`; linked to many `Position` via `PositionTrade` join table
- **Position** → computed from trades; has open/closed status, entry/exit prices, P&L
- **Portfolio** → date range + optional exchange filter for performance analysis; one `default: true` per user enforced via `before_save :clear_other_defaults`
- **SpotAccount** / **SpotTransaction** — spot trading with manual CSV import and cash deposits/withdrawals
- **UserPreference** — key/value store for UI state (e.g., trades index column visibility)

### Background Jobs

Uses **Solid Queue** (PostgreSQL-backed, no Redis). Two databases in `config/database.yml`: `primary` (app data) and `queue` (Solid Queue jobs).

### Frontend

Tailwind CSS + Stimulus + Turbo (Hotwire). No Node build step — uses importmap-rails. Rails runs on port 5000 in development (`Procfile.dev` runs `web` + `css` processes).
