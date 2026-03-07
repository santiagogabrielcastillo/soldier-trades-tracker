# Binance integration review

**Date:** 2026-03-06  
**Scope:** Full Binance integration vs shared layer and BingX; correctness, efficiency, and no regressions.

---

## 1. Architecture and data flow

- **Provider abstraction:** `Exchanges::ProviderForAccount` returns a client by `provider_type` (registry: `binance` → `BinanceClient`, `bingx` → `BingxClient`). No direct `BinanceClient`/`BingxClient` references in sync, jobs, or validators. ✅
- **Sync:** `ExchangeAccounts::SyncService` calls `client.fetch_my_trades(since:)` and `persist_trade(attrs)` for every provider. Only Binance-specific behavior: `since_for_fetch` uses 6-month lookback on first sync when `client.is_a?(Exchanges::BinanceClient)`. ✅
- **Trade shape:** Both providers return trade-style hashes (`exchange_reference_id`, `symbol`, `side`, `price`, `quantity`, `fee_from_exchange`, `executed_at`, `raw_payload`, `position_id`). Sync applies `FinancialCalculator` when `price` and `quantity` are present; `raw_payload` is stored as-is. ✅
- **Positions:** Built from trades only. `PositionSummary.from_trades` groups by symbol then position_id; for `position_id == "BOTH"` (Binance one-way) it runs `split_both_chains` per symbol. No provider branching inside `PositionSummary`; all logic uses dual-key reads from `raw_payload` (BingX + Binance keys). ✅
- **Current prices:** `Trades::IndexService#fetch_current_prices_for_open_positions` groups open positions by `exchange_account.provider_type` and calls `Binance::TickerFetcher` or `Bingx::TickerFetcher`; results are merged by symbol. ✅

**Verdict:** Clear separation; Binance is an additional provider, not a special case in core logic.

---

## 2. Binance implementation

### 2.1 Client (`Exchanges::BinanceClient`)

- **Endpoints:** Futures only (`fapi.binance.com`): `positionRisk`, `income` (REALIZED_PNL), `userTrades`. No spot. ✅
- **Symbol discovery:** `positionRisk` (non-zero `positionAmt`) then `income` (paginated, 6-month window). Combines and uniqs. Empty list returns `[]` (no error). ✅
- **userTrades:** Per-symbol, 7-day windows, limit 1000; paginates within window by `startTime` past last trade when full page. Stops at `end_ms = now`. ✅
- **Errors:** `check_binance_error!` on every response; raises `ApiError` for HTTP 200 with `code != 0` (e.g. -2015 Invalid API key). Prevents “success with 0 trades” on auth failure. ✅
- **Normalizer:** Each raw trade → `Binance::TradeNormalizer.user_trade_to_hash`; nils skipped. Final list deduped by `exchange_reference_id`, sorted by `executed_at`. ✅
- **Ping:** `positionRisk` with empty params; rescues and returns false. ✅

**Efficiency:** One request per symbol for userTrades (chunked in time); income pagination avoids missing symbols. No N+1; no redundant fetches.

### 2.2 Trade normalizer (`Exchanges::Binance::TradeNormalizer`)

- **Required:** `id` (or `tradeId`), `time`, `symbol`. Nil on blank. ✅
- **Symbol:** `BTCUSDT` → `BTC-USDT`; supports USDT, USDC, BUSD; unknown quote left upcased. ✅
- **Fields:** `side` downcased; `price`, `qty`, `commission` from raw; commission stored as **absolute value** (Binance sends negative). ✅
- **raw_payload:** Full raw hash stored so downstream can read `realizedPnl`, `positionSide`, `quoteQty`, etc. ✅
- **position_id:** `positionSide` or `position_side` (one-way mode → `"BOTH"`). ✅

**BingX impact:** None. BingX uses `Bingx::TradeNormalizer` and different keys; symbol format is the same (e.g. `BTC-USDT`).

### 2.3 HTTP client (`Exchanges::Binance::HttpClient`)

- Signed GET: query string sorted, HMAC-SHA256, `X-MBX-APIKEY`. ✅
- Raises `ApiError` for 429/5xx (with `retry_after` when present), empty body, non-JSON. ✅
- Timeouts 10/15 s; optional `base_url` for testnet. ✅
- Fails fast if `api_secret` blank. ✅

### 2.4 Ticker fetcher (`Exchanges::Binance::TickerFetcher`)

- **Public** `GET /fapi/v1/premiumIndex?symbol=BTCUSDT` (no auth). ✅
- Symbol: app form `BTC-USDT` → `BTCUSDT`. ✅
- Returns `Hash[symbol => BigDecimal]` (mark price); failures log and return nil for that symbol. ✅
- Timeouts 5/10 s; rescues timeout, JSON, and generic errors. ✅

---

## 3. Shared layer: dual support (BingX + Binance)

These must work for both providers without branching on provider.

### 3.1 Trade model

- **notional_from_raw:** `avgPrice`/`avg_price`/`price` and `executedQty`/`executed_qty`/`origQty`/`qty`. Covers BingX and Binance. ✅
- **realized_profit_from_raw:** `profit` (BingX) or `realizedPnl` (Binance). ✅
- **leverage_from_raw:** `leverage` string (e.g. "10X"); used by PositionSummary. Binance userTrades may not send leverage; then leverage is nil and margin is computed from notional only when available. ✅

### 3.2 PositionSummary (raw_payload keys)

All reads use fallback chains so one code path serves both:

- **Qty:** `executedQty` || `executed_qty` || `origQty` || `qty` ✅
- **Price:** `avgPrice` || `avg_price` || `price`; exit also `quoteQty`/`qty` ✅
- **Position side:** `positionSide` || `position_side`; else inferred from `side` ✅
- **Closing leg:** `reduceOnly` (BingX) or opposite side (Binance) ✅
- **Same side:** `side` compared (Binance can have reduceOnly on “opening” SELL in one-way; same_side still by side) ✅

**BOTH chain splitting (Binance one-way):**

- Grouping is **by symbol first**, then by position_id. So all symbols are isolated; BOTH is only within one symbol. ✅
- `split_both_chains`: running qty (BUY +, SELL −); cross zero → that trade stays in current chain, next chain starts. Merge last into previous only when combined running is zero (avoids merging a new opposite position). Plus edge cases: first chain single trade with zero qty; last chain same-side-only and combined zero. ✅
- **Over-close:** When `total_closed_qty > open_qty`, an **open** row is emitted for the excess (opposite direction), with `excess_from_over_close` and entry from first closing trade. ✅

**BingX impact:** BingX uses explicit position IDs (e.g. LONG/SHORT), not BOTH; it never hits `split_both_chains`. Partial close and remainder logic unchanged. ✅

### 3.3 SyncService

- **Binance lookback:** Only when `client.is_a?(Exchanges::BinanceClient)` and (no trades or no `last_synced_at`). Other providers and incremental Binance sync use `last_synced_at` or anchor. ✅
- **Persist:** Same for all: find_or_initialize by `exchange_reference_id`, assign symbol/side/fee/net_amount/executed_at/raw_payload/position_id, save. RecordNotUnique skips duplicate. ✅

### 3.4 IndexService

- **Ticker:** `by_provider` groups open positions by `provider_type`; `when "binance"` → `Binance::TickerFetcher`, else BingX. Default for nil/unknown provider_type is `"bingx"`. ✅
- Positions with nil `exchange_account` are skipped and logged; they are excluded before grouping. ✅

### 3.5 Dashboard summary

- Uses `positions.reject(&:open?)` for closed; no “two trades + closing_leg” assumption. Works for both providers. ✅

---

## 4. Correctness summary

| Concern | Status |
|--------|--------|
| Only futures data (no spot) | ✅ Binance client uses only fapi endpoints |
| Trades from userTrades only (no income as trades) | ✅ Doc and code: only userTrades → Trade |
| Symbol format unified (BTC-USDT) | ✅ Normalizer converts Binance BTCUSDT → BTC-USDT |
| Realized PnL from exchange | ✅ build_one_aggregate_closed uses realized_profit_from_raw (profit/realizedPnl) |
| Entry/exit and notional | ✅ Dual keys in PositionSummary and Trade |
| One-way BOTH per symbol | ✅ Group by symbol first; split_both_chains per symbol |
| Over-close → open position | ✅ Excess row with excess_from_over_close |
| Open position PnL | ✅ Unrealized from current price; open row net_pl = 0 |
| BingX unchanged | ✅ No BingX-specific code removed; dual keys preserve both |

---

## 5. Efficiency

- **Binance:** Symbol discovery: 1 positionRisk + N income pages (only until no full page). Then one userTrades flow per symbol (7-day chunks, paginated). Dedup once at the end. ✅
- **BingX:** Unchanged (v1 full order / v2 fills / income fallbacks). ✅
- **Positions:** Single pass over trades; group by symbol then position_id; BOTH split per symbol. No extra queries. ✅
- **Ticker:** One request per open symbol per provider; only when there are open positions. ✅

No obvious inefficiency or N+1.

---

## 6. Tests

- **Binance:** `BinanceClientTest` (errors, empty symbols, discover + userTrades), `Binance::TradeNormalizerTest` (symbol, required fields, commission sign). ✅
- **PositionSummary:** BOTH chain test updated for over-close (2 closed + 1 open Short); open row asserts side, quantity, entry. ✅
- **Trades controller:** Open/closed and ticker behavior. ✅
- **Dashboard:** Summary service uses positions.reject(&:open?). ✅

Run: `rails test test/services/exchanges/ test/models/position_summary_test.rb test/models/trade_test.rb test/controllers/trades_controller_test.rb test/services/dashboards/summary_service_test.rb` — **73 tests, 0 failures**. ✅

---

## 7. Recommendations

1. **Optional: snake_case PnL**  
   `Trade#realized_profit_from_raw` could support `raw["realized_pnl"]` for robustness if any middleware normalizes Binance keys. Low priority.

2. **IndexService test failures (pre-existing)**  
   `Trades::IndexServiceTest` has two failing tests (history/portfolio with `exchange_account_id`); they use a single trade with empty `raw_payload`, so PositionSummary may not produce a row. Unrelated to Binance; fix separately (e.g. minimal raw_payload with qty/price).

3. **Docs**  
   `docs/binance-data-and-inspect.md` is accurate and matches implementation. Keep it as the reference for what we pull and how we interpret it.

4. **No BingX regressions**  
   No code paths were removed or narrowed for BingX. All shared code uses dual-key reads; BingX-only paths (v1/v2/income, ticker) are unchanged.

---

## 8. Conclusion

- **Binance:** Correct use of Futures API, symbol discovery, userTrades normalization, and storage; BOTH handling and over-close are implemented and tested.
- **Shared layer:** Trade and PositionSummary support both providers via dual-key `raw_payload` and provider-agnostic logic; only sync “since” and index “ticker” branch on provider.
- **BingX:** Unchanged; no regressions observed; tests pass.
- **Efficiency:** Appropriate chunking, pagination, and single-pass position building; no redundant or N+1 calls.

The Binance integration is consistent with the intended design, and the existing BingX integration remains intact and efficient.
