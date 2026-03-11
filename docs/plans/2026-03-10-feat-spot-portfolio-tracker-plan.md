# feat: Spot Portfolio Tracker (CSV import, breakeven, PnL, spot prices)

---
title: Spot Portfolio Tracker
type: feat
status: completed
date: 2026-03-10
source_brainstorm: docs/brainstorms/2026-03-10-spot-portfolio-tracker-brainstorm.md
---

## Enhancement Summary

**Deepened on:** 2026-03-10  
**Sections enhanced:** Architecture, Phase 2 (CSV import), Phase 3 (FIFO), Phase 4 (Spot price fetcher), Phase 5 (UI), Technical Considerations.  
**Research sources:** Rails idempotent CSV/upsert patterns, FIFO cost-basis edge cases, file upload security (size/content-type validation), Binance Spot API batch ticker.

### Key Improvements

1. **CSV import:** Prefer database-level idempotency (`upsert_all` with `unique_by: [:spot_account_id, :row_signature]`) for performance; handle `RecordNotUnique` as fallback. Consider row limit (e.g. 2000) and background job for large files.
2. **Spot price:** Binance Spot supports **batch** `GET /api/v3/ticker/price?symbols=["LDOUSDT","AVAXUSDT"]` (weight 4 total)—use one request for all open tokens instead of N per-symbol requests.
3. **File upload security:** Validate file size (e.g. max 5–10 MB), validate content type via magic bytes (Marcel/MimeMagic) not just client MIME, and sanitize filename; store uploads outside web root with non-guessable names if persisting.
4. **FIFO:** Document IRS/per-wallet considerations for future; handle fractional sell matching (consume partial lots) and zero-quantity edge cases in tests.
5. **Data integrity:** Wrap import in transaction; ensure unique index on `(spot_account_id, row_signature)`; consider `validates :row_signature, uniqueness: { scope: :spot_account_id }` plus DB constraint.

### New Considerations Discovered

- Binance Spot ticker/price accepts multiple symbols in one request—simplifies Phase 4 and reduces rate-limit risk.
- Rails `upsert_all` with `unique_by` is the idiomatic way to achieve idempotent bulk insert; use it if batch structure fits (e.g. build array of hashes, then upsert_all).
- File upload validation: 20%+ of breaches relate to improper file handling; strict size + server-side content-type check are mandatory.
- FIFO is the default and least documentation-heavy cost basis method; good for MVP; document that per-wallet/multi-account is already supported by spot_account scope.

---

## Overview

Add a **Spot Portfolio Tracker** module to the existing soldier-trades-tracker app: CSV-only input (no exchange link for spot), content-based deduplication on re-upload, per-token balance, net USD invested, true breakeven, realized and unrealized PnL (FIFO), and current prices from a connected exchange's public spot ticker. Spot data is separate from futures (separate tables); one spot account per user for MVP, with schema ready for multiple spot accounts later.

## Problem Statement / Motivation

- Exchange UIs often show flawed "average buy price" and PnL by ignoring partial sells and cash flow. Users want a single source of truth: net cash flow, true breakeven, and correct realized vs unrealized PnL.
- The app currently tracks only **futures** (API-synced trades). Spot holdings are not supported. Users need to upload a transaction-history CSV and see spot positions with correct accounting.
- Re-uploading the same CSV must not create duplicate transactions (content-based idempotency).
- Current price for unrealized PnL should come from an existing connected exchange's public API (no new credentials), reusing the app's ticker-fetcher pattern.

## Proposed Solution

### Architecture

- **New tables:** `spot_accounts`, `spot_transactions`. No change to `trades`, `positions`, `exchange_accounts`.
- **Spot accounts:** One per user for MVP (e.g. name "Default", `default: true`). Created when the user first uses spot (e.g. visits Spot page or uploads CSV). Schema supports multiple spot accounts later.
- **CSV import:** Parse rows; normalize date (UTC), token (upcased), type (buy/sell), price, amount (strip commas); compute `row_signature` (e.g. SHA256 of normalized string); insert only if `(spot_account_id, row_signature)` does not exist.
- **Position state:** Derived from `spot_transactions` per token: sort by `executed_at` ASC; running balance; when balance hits 0, close epoch; next buy starts new epoch. Breakeven = net_usd_invested / balance; net_usd = sum(buy total_value - sell total_value); MVP: fees discarded.
- **Realized PnL:** FIFO: on each sell, match to oldest buys; realized = sum(sold_qty × (sell_price - buy_price)).
- **Unrealized PnL:** (current_price - breakeven) × balance. **Current price:** fetch from one of the user's connected exchange accounts using that exchange's **public spot ticker** endpoint (no auth). Reuse the pattern of `Positions::CurrentDataFetcher` and per-provider `TickerFetcher`; add spot-specific base URL and path (e.g. Binance: `https://api.binance.com/api/v3/ticker/price`, symbol `TOKENUSDT`; BingX: spot equivalent if available).
- **UI:** New "Spot" entry in main nav (with Trades, Portfolios, etc.). Spot index page: list open/closed spot positions (per token per spot account), with upload CSV action. Reuse layout, auth, and decimal/date helpers.

### ERD (new models)

```mermaid
erDiagram
  users ||--o{ spot_accounts : has
  spot_accounts ||--o{ spot_transactions : has

  users {
    bigint id PK
    string email
  }

  spot_accounts {
    bigint id PK
    bigint user_id FK
    string name
    boolean default
    timestamps
  }

  spot_transactions {
    bigint id PK
    bigint spot_account_id FK
    datetime executed_at
    string token
    string side
    decimal price_usd
    decimal amount
    decimal total_value_usd
    text notes
    string row_signature
    timestamps
  }

  spot_accounts }o--|| users : "user_id"
  spot_transactions }o--|| spot_accounts : "spot_account_id"
```

### Implementation Phases

#### Phase 1: Schema and models

- Migration: create `spot_accounts` (user_id, name, default, timestamps); create `spot_transactions` (spot_account_id, executed_at, token, side, price_usd, amount, total_value_usd, notes, row_signature, timestamps). Unique index on `(spot_account_id, row_signature)`.
- Models: `SpotAccount` (belongs_to :user; has_many :spot_transactions; validations), `SpotTransaction` (belongs_to :spot_account; validations; scope ordered by executed_at).
- Ensure `User` has_many :spot_accounts. Helper or callback: ensure current user has a default spot_account when they first need one (e.g. in Spot controller or service).

**Deliverables:** `db/migrate/..._create_spot_accounts_and_spot_transactions.rb`, `app/models/spot_account.rb`, `app/models/spot_transaction.rb`, `app/models/user.rb` (has_many :spot_accounts).

#### Phase 2: CSV import and row signature

- **Parser:** Accept CSV with headers: Date (UTC-3:00), Token, Type, Price (USD), Amount, Total value (USD), Fee, Fee Currency, Notes. Normalize: parse date to UTC; token trim/upcase; type downcase; price and amount to BigDecimal (strip commas from amount); MVP: ignore Fee/Fee Currency for storage and calculations.
- **Row signature:** Build canonical string from normalized (executed_at ISO8601, token, side, price, amount); hash with SHA256 (or use raw string if short enough for unique index). Store in `spot_transactions.row_signature`.
- **Import service:** `Spot::ImportFromCsvService` (e.g. `call(spot_account:, csv_io:)`). For each row: parse; compute signature; find_or_initialize by (spot_account_id, row_signature); if new record, assign attributes and save. Return counts (created, skipped).
- **Idempotency:** Unique constraint on (spot_account_id, row_signature) so duplicate rows raise or are skipped (handle ActiveRecord::RecordNotUnique or use find_or_create_by).

**Deliverables:** `app/services/spot/import_from_csv_service.rb`, `app/services/spot/csv_row_parser.rb` (or inline parsing), normalization and signature logic. Unit tests for parser and import (duplicate row skips).

**Research Insights (Phase 2)**

- **Best practice:** Prefer database-level idempotency. Use `upsert_all(rows, unique_by: [:spot_account_id, :row_signature])` if building an array of row hashes; Rails 6+ supports this. Alternatively `find_or_create_by(spot_account_id:, row_signature:)` per row with `RecordNotUnique` rescue for race conditions.
- **Performance:** For large CSVs (e.g. 500+ rows), consider batching (e.g. 500 rows per `upsert_all`) to avoid huge single transactions. Disable validations on bulk insert (`validate: false` on upsert) when using DB uniqueness as source of truth.
- **Edge cases:** Normalize decimals to a fixed precision before hashing (e.g. `BigDecimal#to_s('F')`) so "0.5454" and "0.54540" produce the same signature. Strip BOM and normalize line endings when reading CSV.
- **References:** [Rails upsert_all](https://api.rubyonrails.org/classes/ActiveRecord/Persistence/ClassMethods.html#method-i-upsert_all), [activerecord-import unique_by](https://github.com/zdennis/activerecord-import).

#### Phase 3: Position state and FIFO

- **State service:** `Spot::PositionStateService` or equivalent: for a given spot_account, load all spot_transactions ordered by executed_at; group by token; for each token compute: running balance, epochs (new epoch when balance goes 0 then buy), net_usd_invested per epoch, breakeven (net_usd/balance), realized PnL (FIFO: on each sell consume oldest buys), and list of open/closed positions (summary structs or POROs).
- **FIFO:** Maintain a queue of (quantity, price_usd) for buys; on sell, dequeue until sold quantity is matched; realized += sold_qty * (sell_price - buy_price).
- **House money:** When net_usd_invested &lt; 0, breakeven can be reported as 0 or "risk-free"; unrealized still (current_price - 0) × balance or (current_price - breakeven) × balance.

**Deliverables:** `app/services/spot/position_state_service.rb` (or `spot/position_summary.rb`-style builder), FIFO logic, tests with multi-buy/sell and epoch boundaries.

**Research Insights (Phase 3)**

- **FIFO:** Earliest acquired units sold first; minimal documentation burden and aligns with many tax defaults. Per-wallet (per spot_account) tracking already matches "separate inventory" expectations for cost basis.
- **Edge cases:** (1) Fractional sells—consume partial lot: e.g. lot (100, $1.00), sell 30 → leave (70, $1.00), realized = 30 * (sell_price - 1.00). (2) Multiple lots with same timestamp—order by primary key or created_at for deterministic FIFO. (3) Zero balance after sell—close epoch; next buy opens new epoch (no negative balance).
- **House money:** When net_usd_invested &lt; 0, breakeven can be 0 or a "risk-free" label; unrealized = (current_price - 0) * balance is acceptable for display.
- **References:** [Crypto cost basis FIFO](https://chainwisecpa.com/crypto-cost-basis-methods/), [IRS per-wallet tracking](https://www.blockstats.app/blog/crypto-cost-basis-tracking).

#### Phase 4: Spot price fetcher

- **Spot ticker fetchers:** Add or extend exchange clients to support **spot** symbol format and spot API path. Binance: base URL `https://api.binance.com`, path `/api/v3/ticker/price`, symbol `TOKENUSDT` (e.g. LDOUSDT). BingX: research spot ticker path (or skip BingX spot for MVP and only support Binance spot prices).
- **Integration with CurrentDataFetcher:** Either extend `Positions::CurrentDataFetcher` to accept a "mode" (futures vs spot) and list of tokens, or add a dedicated `Spot::CurrentPriceFetcher` that takes user + list of tokens, picks one of the user's exchange_accounts (e.g. first Binance or first any), and calls that provider's spot ticker. Return Hash token => price (symbol key can be token or TOKENUSDT depending on what the UI expects).
- **No connected exchange:** If user has no exchange_account, show unrealized PnL as "—" or "Connect an exchange for live prices" (or at breakeven).

**Deliverables:** `Exchanges::Binance::SpotTickerFetcher` (or extend existing TickerFetcher with spot mode), `Spot::CurrentPriceFetcher` (or equivalent), wire into spot index so open positions get current_prices and unrealized PnL.

**Research Insights (Phase 4)**

- **Binance Spot batch:** `GET https://api.binance.com/api/v3/ticker/price` accepts **`symbols`** (array, e.g. `["LDOUSDT","AVAXUSDT"]`). Weight 4 for the request regardless of symbol count. One request for all open spot tokens instead of N per-symbol calls—reduces latency and rate-limit risk.
- **Response:** Array of `{ "symbol": "LDOUSDT", "price": "0.5454" }`. Map symbol back to token by stripping "USDT" for display key (token => price).
- **Fallback:** If batch fails (timeout, 4xx), log and return {}; UI shows "—" for unrealized PnL. Per-symbol fallback (request one by one) optional for resilience.
- **References:** [Binance Spot Market Data - Symbol Price Ticker](https://developers.binance.com/docs/binance-spot-api-docs/rest-api/market-data-endpoints#symbol-price-ticker).

#### Phase 5: UI — Spot index and CSV upload

- **Routes:** `resources :spot_accounts, only: [:index, :show], path: 'spot'` or `get 'spot', to: 'spot#index'` and `post 'spot/import', to: 'spot#import'`; scope under authenticated user.
- **Nav:** In `layouts/application.html.erb`, add "Spot" link next to Trades and Portfolios.
- **Spot index page:** List spot positions for the user's default spot account: token, balance, net USD invested, breakeven, realized PnL, unrealized PnL (with current price), open/closed. Use `Spot::PositionStateService` and `Spot::CurrentPriceFetcher`. Pagination or "show all" for small sets.
- **CSV upload:** Form with file input; POST to import action; run `Spot::ImportFromCsvService`; redirect back with notice (e.g. "Imported 42 rows, 3 skipped (duplicates)."). Validate file presence and CSV format; show errors (e.g. invalid columns or parse errors).

**Deliverables:** `SpotController` (or `Spot::AccountsController`), `app/views/spot/index.html.erb`, upload form, flash messages, nav link. Authorize: only current_user's spot_account(s).

**Research Insights (Phase 5 — UI & upload security)**

- **File upload security:** (1) **Size:** Enforce max size (e.g. 5–10 MB) server-side before parsing to prevent DoS. (2) **Content type:** Don't trust client MIME; use magic bytes (e.g. `Marcel` gem or `MimeMagic`) to detect text/CSV. (3) **Filename:** Sanitize (strip path, special chars) if storing or logging. (4) Do not execute or eval CSV content; parse only.
- **UX:** After import, show clear feedback: "Imported X rows, Y skipped (duplicates)." On parse error, show first failing row number and message (e.g. "Row 12: invalid date format").
- **References:** [Rails secure file upload](https://moldstud.com/articles/p-best-practices-for-secure-file-uploads-in-ruby-on-rails-apps), [Active Storage validations](https://github.com/rails/rails/pull/35390).

### Out of scope (MVP)

- Fee columns in DB or in PnL calculations (discard fees per brainstorm).
- Multiple spot accounts (schema ready; UI and "add account" deferred).
- Airdrops, transfers in/out (no USD price in CSV).
- BingX spot ticker (if not available or different; can add later).

## Technical Considerations

- **Date handling:** CSV "Date (UTC-3:00)" should be parsed and stored in UTC (e.g. `Time.zone.parse` with CSV timezone or assume UTC-3 and convert). Use `executed_at` for ordering and epoch logic.
- **Decimal precision:** Use `decimal` type with precision/scale (e.g. 20, 8) for price_usd, amount, total_value_usd to match existing trades schema.
- **Performance:** Import of large CSVs (e.g. 1000+ rows) can be run in a background job (Solid Queue) to avoid long request; for MVP, synchronous import with a reasonable row limit (e.g. 2000) is acceptable. Position state is computed from all transactions for the account; if needed later, cache or materialize per-token summaries.
- **Security:** Validate file type (CSV) and size; do not execute or eval CSV content. Authorize spot_account belongs to current_user on every action.
- **DRY:** Reuse `Positions::CurrentDataFetcher` pattern (separate spot fetcher that uses same Net::HTTP/timeout/error handling style). Reuse layout, auth, and helpers (number_to_currency, date formatting).

**Research Insights (Technical — data integrity & security)**

- **Transactions:** Wrap CSV import in `SpotAccount.transaction { ... }` so partial failure rolls back all inserts for that upload. Use savepoints only if mixing read-your-writes within the same request.
- **Constraints:** Add unique index on `(spot_account_id, row_signature)` in migration; add model validation `uniqueness: { scope: :spot_account_id }` for user-facing error messages. DB constraint is source of truth for races.
- **Authorization:** Every spot action must verify `spot_account.user_id == current_user.id` (or load via `current_user.spot_accounts`). No direct `SpotAccount.find(params[:id])` without scope.
- **Decimal precision:** Use same precision/scale as `trades` (e.g. `precision: 20, scale: 8`) for price_usd, amount, total_value_usd for consistency and to avoid rounding drift in FIFO.

## Acceptance Criteria

- [x] User can open a "Spot" page from the main nav and see their spot positions (default spot account).
- [x] User can upload a CSV with columns Date (UTC-3:00), Token, Type, Price (USD), Amount, Total value (USD), Fee, Fee Currency, Notes; rows are imported into spot_transactions; duplicate rows (same normalized content) are skipped.
- [x] Re-uploading the same CSV does not create duplicate transactions (content-based row_signature).
- [x] For each token, current balance, net USD invested, true breakeven, realized PnL (FIFO), and unrealized PnL are correct; when balance hits 0, next buy starts a new epoch (new cost basis).
- [x] If the user has at least one connected exchange, current price for open spot positions is fetched from that exchange's public spot ticker and unrealized PnL is displayed; if no exchange connected, show "—" or message.
- [x] Spot data is separate from futures (no shared tables); futures Trades/Positions unchanged.
- [x] One default spot account per user; created on first use (e.g. first visit to Spot or first import).

## Success Metrics

- CSV import completes without duplicates on re-upload.
- Breakeven and PnL match manual FIFO calculation for a small sample.
- Spot index page loads with correct positions and (when exchange connected) current prices.

## User Flows (SpecFlow-style)

- **First-time spot user:** Visits Spot → no positions → uploads CSV → positions appear; or visits Spot → sees "Upload CSV" → uploads → positions appear. Default spot_account is created on first visit or first import.
- **Returning user:** Visits Spot → sees existing positions; can upload another CSV → new rows added, duplicates skipped; re-upload same file → "0 created, N skipped."
- **User with no connected exchange:** Spot positions show; unrealized PnL shows "—" or "Connect an exchange for live prices" (link to exchange_accounts).
- **User with connected exchange (e.g. Binance):** Open spot positions get current price from Binance spot ticker; unrealized PnL displayed.

## Dependencies & Risks

- **Dependency:** User must have at least one exchange account for live spot prices; otherwise unrealized PnL is not shown (or shown at breakeven). Document in UI.
- **Risk:** CSV format variations (different column names or locales); support the documented format and return clear errors for invalid rows.
- **Risk:** Exchange spot API rate limits or downtime; same as futures ticker — log and skip failed symbols, show partial data.

## References & Research

- **Brainstorm:** `docs/brainstorms/2026-03-10-spot-portfolio-tracker-brainstorm.md` (decisions, schema, edge cases).
- **Current price pattern:** `app/services/positions/current_data_fetcher.rb` (group by provider, call Binance/BingX TickerFetcher); `app/services/exchanges/binance/ticker_fetcher.rb` (futures: fapi.binance.com, premiumIndex). Spot: Binance `https://api.binance.com/api/v3/ticker/price?symbol=LDOUSDT` (public, no auth).
- **Nav and layout:** `app/views/layouts/application.html.erb` (Trades, Portfolios links); add Spot link.
- **Auth and user:** `app/models/user.rb` (has_many exchange_accounts, portfolios); add has_many spot_accounts; ensure default spot_account for current_user in Spot flow.
- **Routes:** `config/routes.rb` — add spot routes under authenticated scope.
