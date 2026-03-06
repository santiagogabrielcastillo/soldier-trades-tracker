# feat: Add Binance USDⓈ-M Futures as exchange provider

---
title: Add Binance USDⓈ-M Futures as exchange provider
type: feat
status: completed
date: 2026-03-06
source_brainstorm: docs/brainstorms/2026-03-06-add-binance-exchange-brainstorm.md
---

## Enhancement Summary

**Deepened on:** 2026-03-06  
**Sections enhanced:** Proposed Solution (endpoints, response fields), Technical Considerations (auth, ticker, income fallback).  
**Research sources:** Binance Futures API docs (Account Trade List, Mark Price, Income History), BingX TickerFetcher pattern.

### Key improvements

1. **userTrades response:** Use `id` as exchange_reference_id; `commission` is string (e.g. "-0.07819010") — take absolute value for fee_from_exchange; `time` in ms; `positionSide` (LONG/SHORT) in raw_payload for later closing_leg logic. No `orderId` in response body needed for reference id.
2. **Income fallback:** `GET /fapi/v1/income` with `incomeType=REALIZED_PNL`, `startTime`/`endTime` (since to now), `limit` 1000. Extract unique `symbol` from records; then fetch userTrades per symbol. Income returns most recent first when no time range; with time range, paginate if >1000 records (chunk time or use fromId-style pagination if available).
3. **Current price:** Use **Mark Price** — `GET /fapi/v1/premiumIndex?symbol=BTCUSDT` (public, no auth). Response field `markPrice` (string). Weight 1 per symbol. Same base URL as signed API; no auth. Binance TickerFetcher: convert symbol BTC-USDT → BTCUSDT for request; parse `markPrice` from response.
4. **Testnet:** Binance General Info: REST testnet base URL `https://testnet.binancefuture.com`. Use for `base_url` when testnet enabled.

### New considerations

- **Income pagination:** If user has many REALIZED_PNL rows in a range, income returns max 1000. For symbol discovery we only need unique symbols — one or two income calls (e.g. since to now in one chunk, or split into 30-day chunks) may suffice; if still missing symbols, accept that first sync may be partial and next sync picks up more.
- **Commission sign:** Binance returns commission as negative (cost). Store as positive in fee_from_exchange or keep sign and let FinancialCalculator handle; BingX normalizer uses raw value — align so net_amount/fee semantics match.

---

## Overview

Add Binance USDⓈ-M Futures as a second exchange so users can link a Binance Futures account and sync trades into the same trades table and flows (dashboard, trades index, portfolios) as BingX. The client implements the existing `BaseProvider` contract, is registered in `ProviderForAccount`, and supports testnet via configurable base URL. Current price for unrealized PnL is provided via a Binance Futures ticker fetcher.

## Problem Statement / Motivation

- Users who trade on Binance USDⓈ-M Futures cannot today link that account; only BingX is implemented.
- `ExchangeAccount` already allows `provider_type: "binance"` and the sync pipeline is provider-agnostic; only the Binance client and registry entry are missing.
- Adding Binance gives a second exchange with minimal changes to jobs, validator, or UI.

## Proposed Solution

1. **Binance HTTP client** — Signed GET for `https://fapi.binance.com` (and testnet): HMAC SHA256 on query string, `X-MBX-APIKEY` header, `timestamp` + `signature` in query. Mirror structure of `Exchanges::Bingx::HttpClient` (timeouts, 429/5xx → `Exchanges::ApiError`, JSON parse errors). Optional `base_url` for testnet (`https://testnet.binancefuture.com`).

2. **Symbol discovery** — Binance `GET /fapi/v1/userTrades` requires `symbol`. Strategy: call `GET /fapi/v2/positionRisk` to get symbols with current positions (`positionAmt` != 0). If that list is empty (no open positions), call `GET /fapi/v1/income` with `incomeType=REALIZED_PNL` and time range from `since` to discover symbols that had closed PnL, then fetch userTrades for those symbols. Deduplicate and iterate each symbol in 7-day chunks (Binance limit).

3. **Trade fetch** — For each symbol, call `GET /fapi/v1/userTrades` with `symbol`, `startTime`, `endTime` (max 7 days), `limit` 1000. Chunk from `since` to now in 7-day windows; collect all fills and normalize to the shared trade hash.

4. **Normalizer** — New module (e.g. `Exchanges::Binance::TradeNormalizer`) mapping Binance userTrades payload to: `exchange_reference_id` (e.g. trade `id`), `symbol` (normalized to `BTC-USDT`), `side`, `price`, `quantity`, `fee_from_exchange` (commission), `executed_at`, `raw_payload`, `position_id` if present. Symbol: convert `BTCUSDT` → `BTC-USDT` (insert hyphen before quote asset).

5. **BinanceClient** — Class `Exchanges::BinanceClient < BaseProvider`. Constructor `(api_key:, api_secret:, base_url: nil)`; default base URL production. `#fetch_my_trades(since:)`: discover symbols (positionRisk then income fallback), then for each symbol fetch userTrades in 7-day chunks, normalize, deduplicate by `exchange_reference_id`, sort by `executed_at`, return array. `self.ping(api_key:, api_secret:)`: one signed request (e.g. positionRisk with no symbol, or userTrades for one symbol with limit=1); return true/false for validator.

6. **Registry** — In `Exchanges::ProviderForAccount::REGISTRY` add `"binance" => "Exchanges::BinanceClient"`. No changes to sync job, dispatcher, or `ExchangeAccountKeyValidator`.

7. **Exchange account form** — Support selecting Binance: change `exchange_accounts/new` from hidden "bingx" to a select (or two options) for `provider_type`: BingX and Binance. Show provider-specific copy (e.g. "Read-only API key from Binance Futures → API Management").

8. **Current price for open positions** — `Trades::IndexService` currently calls `Exchanges::Bingx::TickerFetcher` only. Extend to support multiple providers: group open positions by `exchange_account.provider_type`; for BingX accounts call `Bingx::TickerFetcher` with those symbols; for Binance accounts call a new `Exchanges::Binance::TickerFetcher` (or equivalent) with those symbols (convert `BTC-USDT` → `BTCUSDT` for Binance API). Merge results into one `current_prices` hash keyed by symbol (already `BTC-USDT`). Implement Binance public ticker (e.g. `GET /fapi/v1/ticker/price` or mark price) and a fetcher that returns `Hash[symbol => BigDecimal]` for the open symbols.

### Research insights (Proposed Solution)

- **userTrades response fields:** `id`, `symbol`, `side`, `price`, `qty`, `commission` (string, negative), `realizedPnl`, `positionSide`, `time` (ms). Use `id` for exchange_reference_id; normalize symbol to hyphen form; put full object in raw_payload. Commission: use absolute value for fee_from_exchange so FinancialCalculator semantics match.
- **Income for symbol discovery:** `GET /fapi/v1/income` — params `incomeType=REALIZED_PNL`, `startTime`, `endTime` (ms), `limit` 1000. Response array with `symbol`, `incomeType`, `income`, `time`. Collect unique symbols; then call userTrades per symbol. Weight 100 per income call; one or two calls (e.g. full range or 6-month chunk) usually enough to get symbol list.
- **Mark price (current price):** Public endpoint `GET /fapi/v1/premiumIndex?symbol=BTCUSDT`. No auth. Response: `{ "symbol": "BTCUSDT", "markPrice": "11793.63...", ... }`. Use `markPrice` for unrealized PnL. Weight 1 per symbol. Base URL same as signed API (`https://fapi.binance.com`); testnet `https://testnet.binancefuture.com`.

## Technical Considerations

- **Auth:** Binance signed requests: query string key-value pairs sorted, append `timestamp`, then `signature = HMAC_SHA256(secret, query_string)` hex; header `X-MBX-APIKEY: api_key`. Same pattern as General Info doc. Use `recvWindow` (e.g. 5000 ms) if needed.
- **Rate limits:** Binance returns 429 with rate limit info; handle like BingX (raise `ApiError` with optional `retry_after`). userTrades weight 5, positionRisk 5, income 100; chunking and per-symbol requests stay within reasonable limits for typical accounts.
- **6-month limit:** Binance userTrades only returns last 6 months. Document in code or runbook; first sync for old accounts will only get 6 months of data.
- **Empty symbol list:** If positionRisk and income both yield no symbols, return empty trades array (no error). Next sync after user trades will discover symbols.
- **Testnet:** Client accepts `base_url`; exchange account form or a future setting could pass testnet URL for development. No DB column required for first slice if we only support production; testnet can be enabled via env or same form (e.g. "Use testnet" checkbox that sets base_url when creating client).
- **PositionSummary:** Consumes `raw_payload` and symbol; symbol is already normalized to `BTC-USDT`. No change to PositionSummary for Binance; ensure normalizer puts `positionSide` / `position_id` in raw_payload if Binance provides it so closing_leg? and entry/exit logic can be extended later if needed.

### Research insights (Technical)

- **Auth (Binance):** Query string: sort key-value pairs, append `timestamp` (ms), then `signature = HMAC_SHA256(secret_key, query_string)` hex-encoded. Header `X-MBX-APIKEY: api_key`. Optional `recvWindow` (default 5000). Same as [General Info](https://developers.binance.com/docs/derivatives/usds-margined-futures/general-info).
- **503 handling:** Binance General Info: on 503 with "Unknown error, please check your request or try again later" the execution status is UNKNOWN (may have succeeded). Do not treat as hard failure; consider idempotent sync (find_or_initialize_by exchange_reference_id) so duplicate requests don't create duplicate trades.
- **Ticker base URL:** Mark price is on same host as fapi (`fapi.binance.com`). Binance TickerFetcher can use a constant BASE_URL; no credentials. Match BingX TickerFetcher pattern: one GET per symbol, timeouts 5s/10s, log and skip on non-200 or parse error, return Hash[symbol => BigDecimal].

## Acceptance Criteria

- [x] **Registry:** `Exchanges::ProviderForAccount::REGISTRY` includes `"binance" => "Exchanges::BinanceClient"`. Sync job and validator work for `provider_type: "binance"` without code branches.
- [x] **BinanceClient:** Implements `#fetch_my_trades(since:)` returning array of normalized trade hashes (exchange_reference_id, symbol as BTC-USDT, side, price, quantity, fee_from_exchange, executed_at, raw_payload, position_id). Implements `self.ping(api_key:, api_secret:)` for key validation.
- [x] **Symbol discovery:** Uses GET /fapi/v2/positionRisk to get symbols with positions; if empty, uses GET /fapi/v1/income (REALIZED_PNL) to discover symbols; then GET /fapi/v1/userTrades per symbol in 7-day chunks.
- [x] **Normalization:** Binance userTrades payload mapped to shared hash; symbol normalized to hyphen form (e.g. BTCUSDT → BTC-USDT).
- [x] **Testnet:** Client accepts optional `base_url` (e.g. testnet); documented or selectable so dev/test can use testnet.
- [x] **Link account:** User can choose Binance (or BingX) on "Link exchange account" and submit read-only API key/secret; validation uses BinanceClient.ping.
- [x] **Current price:** Trades index shows unrealized PnL for open positions from Binance accounts. Either `Trades::IndexService` calls a Binance ticker fetcher for Binance-origin open symbols and merges with BingX prices, or a small router does it; symbols passed to Binance API in exchange-native form (BTCUSDT).
- [x] **Tests:** Unit tests for Binance normalizer (symbol format, required fields); tests for BinanceClient#fetch_my_trades with stubbed HTTP (symbol discovery + chunking); ProviderForAccount test updated for binance; integration test or controller test that linking Binance and syncing returns 200 and creates trades (or stub client).

## Success Metrics

- Users with a Binance Futures account can link it and sync trades.
- Trades from Binance appear in dashboard, trades index, and portfolios like BingX.
- Unrealized PnL for open Binance positions shows when current price is available.
- No regression for BingX-only users.

## Dependencies & Risks

- **Risks:** Binance API changes (document endpoints and versions); 6-month history limit may surprise users with old accounts.
- **Dependencies:** None internal beyond existing ExchangeAccount, Trade, sync job, and IndexService.

## References & Research

### Internal

- Brainstorm: `docs/brainstorms/2026-03-06-add-binance-exchange-brainstorm.md`
- Provider contract: `app/services/exchanges/base_provider.rb`
- Registry: `app/services/exchanges/provider_for_account.rb`
- BingX HTTP + normalizer: `app/services/exchanges/bingx/http_client.rb`, `app/services/exchanges/bingx/trade_normalizer.rb`
- Sync: `app/services/exchange_accounts/sync_service.rb`
- Ticker: `app/services/exchanges/bingx/ticker_fetcher.rb`; `app/services/trades/index_service.rb` (fetch_current_prices_for_open_positions)
- Exchange form: `app/views/exchange_accounts/new.html.erb`

### External

- [Binance USDⓈ-M Futures – General Info](https://developers.binance.com/docs/derivatives/usds-margined-futures/general-info) (base URL, auth, 503 handling, testnet URL)
- [Account Trade List (userTrades)](https://developers.binance.com/docs/derivatives/usds-margined-futures/trade/rest-api/Account-Trade-List) — response: id, symbol, side, price, qty, commission, realizedPnl, positionSide, time
- [Position Information V2 (positionRisk)](https://developers.binance.com/docs/derivatives/usds-margined-futures/trade/rest-api/Position-Information-V2) — symbol, positionAmt for symbol discovery
- [Get Income History](https://developers.binance.com/docs/derivatives/usds-margined-futures/account/rest-api/Get-Income-History) — GET /fapi/v1/income, incomeType=REALIZED_PNL, limit 1000
- [Mark Price](https://developers.binance.com/docs/derivatives/usds-margined-futures/market-data/rest-api/Mark-Price) — GET /fapi/v1/premiumIndex (public), markPrice for current price
