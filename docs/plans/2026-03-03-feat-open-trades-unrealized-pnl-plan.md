# feat: Open trades with unrealized PnL and ROI

---
title: Open trades with unrealized PnL and ROI
type: feat
status: completed
date: 2026-03-03
source_brainstorm: docs/brainstorms/2026-03-03-open-trades-unrealized-pnl-brainstorm.md
---

## Enhancement Summary

**Deepened on:** 2026-03-03  
**Sections enhanced:** Technical Considerations, Implementation outline, Dependencies & Risks  
**Research sources:** BingX Swap V2 API docs, Rails external-API best practices, existing codebase (Bingx::HttpClient timeouts, level1 robustness plan), workspace review rules (Rails, performance, architecture).

### Key improvements

1. **Concrete BingX endpoint** — Use `GET /openApi/swap/v2/quote/ticker` with `symbol` query param (public, no auth). Parse response for price field (e.g. `lastPrice` or `price`); document or config the key and handle missing/empty.
2. **Timeouts and resilience** — Public ticker client should set explicit `open_timeout` and `read_timeout` (e.g. 5s / 10s) so one slow symbol doesn’t block page load. Rescue `Net::OpenTimeout`, `Net::ReadTimeout`, and `JSON::ParserError`; log and return nil for that symbol.
3. **Service boundary** — Keep a dedicated ticker/price fetcher in `app/services` (single responsibility); `Trades::IndexService` orchestrates (build positions → collect open symbols → call fetcher → pass prices). Aligns with existing `Bingx::HttpClient` vs `BingxClient` separation.
4. **Performance** — Fetch only for unique open-position symbols; serial requests are acceptable for typical N (e.g. 1–10). If N grows, consider batching or parallel HTTP later; avoid N+1 by fetching before pagination for the full set.
5. **No retries** — Plan already specifies no retry on ticker failure; matches “don’t retry 4xx” and keeps page load predictable.

### New considerations

- **Response parsing:** BingX ticker response shape may use `lastPrice`, `price`, or similar; implement with a single extracted method and handle nil/blank so API changes can be handled in one place.
- **Symbol format:** Ensure symbols passed to the ticker match exchange format (e.g. `BTC-USDT`); reuse existing `Trade#symbol` as stored by sync.

---

## Overview

Show open positions in the existing trades table with the same attribute columns as closed trades. Open rows are visually distinguished (e.g. "Open" in the date column) and display **unrealized** PnL and ROI using the **current price** of each symbol. Current price is fetched only when the trades page is loaded (no polling or auto-refresh). Filters (Open / Closed) are out of scope and will be added later.

**Context:** Brainstorm 2026-03-03. Approach 1: same table, price on page load, exchange public ticker. SpecFlow analysis captured in `docs/brainstorms/2026-03-03-open-trades-unrealized-pnl-spec-flow-analysis.md`.

---

## Problem Statement / Motivation

- Closed trades already show PnL, ROI, margin, etc. Open positions appear in the same table today but with `close_at` set to the last (open) fill date and net_pl/ROI as 0 or N/A.
- Users want to see **unrealized** PnL and ROI for open positions, which requires the **current market price** for each traded pair.
- Price should be fetched only on page reload (no automatic background refresh initially).

---

## Proposed Solution

1. **Identify open positions** — A position is "open" when it has no closing leg (existing logic: `build_one_aggregate` in `PositionSummary` when `closing.empty?`). Add a predicate `PositionSummary#open?` so the view and index service can distinguish open rows.
2. **Fetch current price on index load** — When rendering the trades index, collect the set of unique symbols that have at least one open position in the **full** result set (before pagination). For each symbol, call the exchange **public** ticker API (no auth). Pass a `symbol => price` map into the presentation layer. If there are zero open positions, do not call the ticker.
3. **Unrealized PnL and ROI** — For each open row, compute unrealized PnL and unrealized ROI using the fetched current price (when available). Use the same semantics as closed: margin-based ROI; direction-aware PnL (long: profit when price up; short: profit when price down). If price is missing (API failure or symbol not supported), show "—" for unrealized metrics.
4. **UI** — In the "Closed" column, show "Open" for open positions instead of a date. For open rows, display unrealized PnL in the Net PnL column and unrealized ROI in the ROI column when price is available; otherwise "—". Balance column: use the same running balance as today (open rows participate in the same running balance). No new tabs or filters in this iteration.

---

## Technical Considerations

- **Open predicate:** `PositionSummary#open?` returns true when the position has no closing leg: `trades.none? { |t| closing_leg?(t) }`. This matches positions built by `build_one_aggregate` with no closing trades.
- **Price source:** BingX (current provider) exposes a **public** ticker/quote endpoint for swap (no API key). Use **GET /openApi/swap/v2/quote/ticker** with query param `symbol` (e.g. `?symbol=BTC-USDT`). Use a simple unauthenticated GET (e.g. `Net::HTTP` or a small public client); do not use `Bingx::HttpClient`, which is signed. One request per unique symbol with open positions; cache result in memory for the request.
- **Fetch scope:** Fetch prices for every unique symbol that has an open position in the **full** list of positions (before pagination) so that when the user navigates to page 2, open positions there already have prices without a second request.
- **Unrealized formulas:**
  - Entry price: from opening trade `notional_from_raw / open_quantity` or `raw_payload["avgPrice"]`. Remaining quantity for a fully open position = `open_quantity` (no partial close in scope).
  - Unrealized PnL (long): `(current_price - entry_price) * open_quantity` (in quote/USDT).
  - Unrealized PnL (short): `(entry_price - current_price) * open_quantity`.
  - Unrealized ROI: `(unrealized_pnl / margin_used) * 100` when `margin_used` present and non-zero; otherwise "—".
  - Show "—" when `current_price` is nil, or when `margin_used`/`open_quantity`/entry price is missing or zero as needed.
- **Ticker failure:** On HTTP error or parse failure for a symbol, log a warning, set that symbol's price to nil, and show "—" for unrealized metrics. Do not fail the page; do not retry within the request.
- **Partial closes:** Only positions with **no** closing leg are considered "open" for this feature. A row that represents "remaining open after partial close" is out of scope (current `PositionSummary` builds one row per closing leg; no separate row for remainder).
- **Sorting:** Keep existing order: by `close_at` desc (open positions use last fill time as `close_at`). No special grouping of open vs closed.
- **Balance:** Running balance is computed over all positions (open and closed) as today; open rows show the same balance they would get from `assign_balance!`. No "—" for balance on open rows.

### Research insights (Technical)

**BingX public ticker**

- Use **GET /openApi/swap/v2/quote/ticker** with query param `symbol` (e.g. `?symbol=BTC-USDT`). No authentication; same base URL as signed API (`https://open-api.bingx.com`). Official docs: https://bingx-api.github.io/docs/#/swapV2/introduce
- Response format: parse JSON and read price from the field used by the API (e.g. `lastPrice` or `price`). Isolate parsing in one method (e.g. `extract_price_from_ticker_response(data)`) and return `nil` for missing/blank/non-numeric so API changes are localized.

**Resilience and timeouts**

- Set **open_timeout** (e.g. 5s) and **read_timeout** (e.g. 10s) on the HTTP client used for ticker so a slow or stuck exchange doesn’t block the whole page. Existing signed client uses 10s/15s (`app/services/exchanges/bingx/http_client.rb`); public ticker can be slightly stricter.
- Rescue **Net::OpenTimeout**, **Net::ReadTimeout**, **Timeout::Error**, and **JSON::ParserError**; log warning with symbol and error message; set that symbol’s price to nil and continue. Do not retry (plan requirement; also avoids amplifying load on a failing endpoint).

**Service structure**

- Dedicated fetcher (e.g. `Exchanges::Bingx::TickerFetcher` or `Exchanges::CurrentPriceFetcher`) keeps HTTP and parsing out of `Trades::IndexService` and preserves single responsibility. IndexService stays an orchestrator: load trades → build positions → collect open symbols → call fetcher with symbol list → merge prices into result.

**Performance**

- One request per unique symbol with open positions is acceptable for small N. If the number of open symbols grows (e.g. 20+), consider batching (if the exchange supports multiple symbols per request) or parallel requests in a follow-up; not required for initial scope.

---

## Acceptance Criteria

- [x] **Open indicator:** Rows with no closing leg show "Open" in the Closed column (or equivalent visual distinction); closed rows show the close date. Closed rows continue to show realized net_pl and roi_percent; open rows show unrealized when price is available.
- [x] **Price on load:** On trades index load, the app fetches current price for every unique symbol that has at least one open position in the full result set (before pagination). If there are zero open positions, no ticker requests are made.
- [x] **Unrealized PnL:** Open rows display unrealized PnL in the Net PnL column when current price is available; formula: direction-aware (long/short) as in Technical Considerations. Show "—" when price is unavailable.
- [x] **Unrealized ROI:** Open rows display unrealized ROI in the ROI column when current price and margin_used are available; formula `(unrealized_pnl / margin_used) * 100`. Show "—" when price or margin is unavailable.
- [x] **Balance:** Open rows use the same running balance as closed rows (no "—" for balance).
- [x] **Ticker failure:** If the ticker request fails for a symbol, the page still renders; that symbol's open positions show "—" for unrealized PnL and ROI; log a warning.
- [x] **No polling:** Price is only fetched on full page load (no background refresh, no polling).
- [x] **Partial closes:** Only positions with no closing leg are treated as open. "Remaining open after partial close" is out of scope.

---

## Success Metrics

- Users see unrealized PnL and ROI for open positions when they load the trades page.
- Page load does not depend on ticker success (graceful degradation to "—").
- No new background jobs or recurring fetches for price.

---

## Dependencies & Risks

- **BingX public endpoint:** Reliance on BingX swap market data endpoint URL and response shape. Document or config the path; handle response changes with nil and "—".
- **Multi-exchange:** Current app uses BingX. If another exchange is added, ticker fetching may need to be provider-specific (per-symbol or per-exchange). Out of scope for this plan; single provider assumed.

### Research insights (Risks)

- **Endpoint stability:** Public market-data endpoints are usually more stable than trading endpoints; still, isolate the URL and response parsing so a future change (path or JSON shape) is fixed in one place. Consider a constant or config for the ticker path and a single `extract_price_from_ticker_response`-style method.
- **Rate limits:** Public ticker endpoints often have higher limits than authenticated ones. For “one request per symbol on page load” with typical N under 10, risk is low. If adding many symbols or background refresh later, add rate limiting or backoff.

---

## Implementation outline

1. **PositionSummary** — Add `#open?` (true when no closing leg). Add `#entry_price` (from first trade) and `#unrealized_pnl(current_price)` / `#unrealized_roi_percent(current_price)` that return nil when price or required data is missing.
2. **Price fetcher** — New service or module (e.g. `Exchanges::Bingx::TickerFetcher` or `Exchanges::CurrentPriceFetcher`) that, given a list of symbols, performs unauthenticated GET(s) to BingX public ticker and returns `Hash[symbol => BigDecimal]`. Call from `Trades::IndexService` (or controller) after building positions; collect symbols from `positions.select(&:open?).map(&:symbol).uniq`.
3. **Trades::IndexService** — After `from_trades_with_balance`, if any position is open, fetch prices for open-position symbols; pass `current_prices` (hash) in the result. Controller passes it to the view (e.g. `@current_prices`).
4. **View** — In `app/views/trades/index.html.erb`: for each row, if `pos.open?`, show "Open" in the Closed column; for ROI and Net PnL, use `pos.unrealized_roi_percent(@current_prices[pos.symbol])` and `pos.unrealized_pnl(@current_prices[pos.symbol])` when present, else "—". Balance unchanged.
5. **Tests** — Unit tests for `#open?`, `#entry_price`, `#unrealized_pnl`, `#unrealized_roi_percent`; service test for price fetcher (with stubbed HTTP); request test for index with open positions and with ticker failure.

### Research insights (Implementation)

**PositionSummary**

- `#open?`: `trades.none? { |t| closing_leg?(t) }` — minimal and consistent with existing `closing_leg?`. No new state.
- `#entry_price`: Prefer from opening trade’s `raw_payload["avgPrice"]` if present and parseable; else `notional_from_raw / open_quantity` when `open_quantity` positive. Return nil otherwise so callers can show "—".
- `#unrealized_pnl(current_price)` and `#unrealized_roi_percent(current_price)`: Return `nil` when `current_price` is nil/blank, or when `open?` is false (closed positions use existing `net_pl`/`roi_percent`). Use BigDecimal and round to 8 decimals for consistency with `PositionSummary` and `FinancialCalculator`.

**Price fetcher**

- Interface: `fetch_prices(symbols:) => Hash[String, BigDecimal]`. For each symbol, GET ticker; parse; on success store `symbol => price`; on failure (timeout, non-200, parse error) log and skip that symbol. Return only symbols that succeeded so view can use `@current_prices[pos.symbol]` and get nil for failures.
- Use `Net::HTTP` (or a thin wrapper) without API key/signature; separate from `Bingx::HttpClient` so auth and public endpoints stay clearly separated. Consider a module under `Exchanges::Bingx` for future multi-exchange ticker abstraction.

**View**

- Keep logic minimal: `pos.open? ? "Open" : pos.close_at&.strftime(...)` for the Closed column; for ROI and Net PnL use `pos.unrealized_roi_percent(@current_prices[pos.symbol])` and `pos.unrealized_pnl(@current_prices[pos.symbol])` when `pos.open?`, else existing `pos.roi_percent` and `pos.net_pl`. Use same formatting helpers (`format_money`, `number_with_precision`) and color classes (emerald/red) as closed rows for consistency.

**Edge cases**

- Empty symbol list: fetcher returns `{}`; no HTTP calls.
- Ticker returns 200 but unexpected JSON shape: parsing returns nil for that symbol; log warning with symbol.
- Entry price zero or nil: `unrealized_pnl` and `unrealized_roi_percent` return nil (avoid division by zero and nonsensical ROI).

---

## References & Research

- Brainstorm: `docs/brainstorms/2026-03-03-open-trades-unrealized-pnl-brainstorm.md`
- SpecFlow analysis: `docs/brainstorms/2026-03-03-open-trades-unrealized-pnl-spec-flow-analysis.md`
- Existing patterns: `app/models/position_summary.rb` (build_summaries, closing_leg?, margin_used, roi_percent), `app/services/trades/index_service.rb`, `app/views/trades/index.html.erb`
- BingX: Swap V2 market data (public ticker) — https://bingx-api.github.io/docs/#/swapV2/introduce  
- BingX swap ticker: **GET /openApi/swap/v2/quote/ticker?symbol=SYMBOL** (public, no auth)  
- Rails external APIs: timeouts (open/read), rescue Net::OpenTimeout/Net::ReadTimeout/JSON::ParserError (see `docs/plans/2026-02-27-feat-level1-technical-robustness-plan.md`), service objects in `app/services`
