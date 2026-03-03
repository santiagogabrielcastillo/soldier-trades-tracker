# Open Trades with Unrealized PnL — Spec Flow Analysis

**Date:** 2026-03-03  
**Feature:** Open trades in same trades table with unrealized PnL/ROI; current price on page load only.  
**Reference:** [2026-03-03-open-trades-unrealized-pnl-brainstorm.md](./2026-03-03-open-trades-unrealized-pnl-brainstorm.md)

---

## 1. User Flow Overview

### Flow 1: User loads trades index (happy path — has open and closed positions)

1. User navigates to Trades (History or Portfolio view).
2. Controller calls `Trades::IndexService.call` → loads trades, `PositionSummary.from_trades_with_balance` builds rows (closed legs + open aggregates).
3. **New:** Service (or a dedicated step) collects unique symbols from **open** positions only and fetches current price per symbol from exchange public ticker (e.g. BingX).
4. **New:** Each open row is enriched with `current_price` (or nil if fetch failed); closed rows unchanged.
5. View renders table: for each row, if open → show "Open" (or badge) in Closed column; show unrealized PnL and unrealized ROI when `current_price` present, else "—" for those two cells; Balance/Margin/Commission/etc. as today.
6. User sees mixed list (open and closed), open rows visually distinct, with unrealized metrics where price is available.

**Variants:**

- **1a. Portfolio view with date range:** Same as above; only trades in portfolio range are loaded, so open positions may be fewer (or zero) if no open position’s open_at falls in range. **Spec gap:** Should an open position opened before the portfolio start date appear if it’s still open? (Currently `trades_in_range` likely filters by `executed_at`; an open position has no close trade, so it would appear if any of its trades fall in range.)
- **1b. History view (all-time):** All user trades → open and closed positions; ticker fetched for symbols of open positions only.
- **1c. Multiple open positions, same symbol:** One ticker request per unique symbol; same price reused for all open rows with that symbol (e.g. two BingX accounts, same symbol → one fetch). **Edge:** If we later support multiple exchanges, ticker is per-exchange; same symbol on different exchanges may need separate fetches.

### Flow 2: User loads trades index — no open positions

1. User has only closed positions (or no trades).
2. Service builds positions as today; no rows are "open."
3. **New:** No symbols to fetch → no ticker calls (or empty price map).
4. Table renders as today: all rows show closed date, realized ROI, Net PnL, Balance. No "Open" badge, no unrealized columns behavior change.
5. **Acceptance:** Page load must not call ticker API when there are zero open positions.

### Flow 3: User loads trades index — open positions but ticker unavailable

1. User has one or more open positions.
2. Service collects symbols for open positions; requests current price (e.g. BingX public ticker).
3. Ticker request fails (network error, 429, 5xx, timeout) or returns no price for a symbol.
4. **New:** For those symbols, `current_price` is nil (or missing from map).
5. View renders open rows with "—" for unrealized PnL and unrealized ROI; other columns (Margin used, Commission, Balance, etc.) still shown. Open rows still visually distinguished (e.g. "Open" in date column).
6. **Acceptance:** No partial failure of the whole page; table loads, only unrealized metrics show "—".

### Flow 4: User loads trades index — partial ticker success (multiple symbols)

1. User has open positions in BTC-USDT and ETH-USDT.
2. Ticker fetch for BTC-USDT succeeds; for ETH-USDT fails (or times out).
3. **New:** Open row for BTC-USDT shows unrealized PnL/ROI; open row for ETH-USDT shows "—" for unrealized metrics.
4. **Acceptance:** One failure must not block or clear prices for other symbols; per-symbol failure handling.

### Flow 5: User refreshes page to get updated price

1. User already on trades index with open positions and unrealized metrics.
2. User refreshes (F5 or reload).
3. Full page reload → IndexService runs again → ticker fetched again → new prices → unrealized PnL/ROI recalculated.
4. **Acceptance:** No polling; refresh is the only way to update current price (per spec).

### Flow 6: Pagination (open and closed mixed)

1. User has many positions; pagy limit 25; open and closed are interleaved (sort by `close_at` desc — for open, `close_at` is last fill time).
2. **New:** Ticker should be fetched only for open positions **on the current page** to avoid fetching prices for 100 open symbols when user sees 25 rows. **Alternative:** Fetch for all open positions in the full result set so that when user goes to page 2, prices are already there. **Spec gap:** Not specified — see "Missing specs" below.
3. **Acceptance (to add):** Define whether current price is fetched for (a) all open positions in the dataset, or (b) only open positions on the current page.

---

## 2. Edge Cases

| Edge case | Description | Spec / handling |
|-----------|-------------|------------------|
| **No open positions** | Only closed positions or no trades. | No ticker calls; table as today. |
| **API failure (ticker)** | BingX (or provider) ticker returns 4xx/5xx, timeout, or non-JSON. | Show "—" for unrealized PnL/ROI for affected symbols; do not fail page load. |
| **Partial closes** | Position has one or more closing legs plus still-open quantity. | Current model: closed legs → one row per leg (`build_one_leg`); remaining open → one `build_one_aggregate` for the open part? **Check:** `build_summaries` only returns `build_one_aggregate(trades)` when `closing.empty?` — so it does not split "partial close" into closed legs + one open row. So a position with 2 closing trades and 1 open trade yields 2 closed rows only; the "remaining" open quantity is not a separate row. **Gap:** Spec says "partial closes" — need to confirm if the current behavior (only fully closed legs get rows; one aggregate row for "no close" only) is intended, or if we need a row for "remaining open quantity" after partial closes. |
| **Multiple symbols** | Several open positions, different symbols. | One ticker request per unique symbol (or per exchange+symbol if multi-exchange); reuse price for same symbol. |
| **Same symbol, multiple accounts** | Two BingX accounts both with BTC-USDT open. | One ticker for BTC-USDT; same price for both rows (BingX ticker is global). If later multi-exchange: Binance vs BingX same symbol may need two fetches. |
| **Single-fill position (no position_id)** | Trade with no closing leg, single fill. | Already built as one row via `build_one_aggregate`; `close_at` = that trade’s `executed_at`. Treated as "open" for display and unrealized metrics. |
| **Margin or quantity missing** | Open position row has `margin_used` nil or open_quantity zero. | Unrealized ROI formula (PnL / effective_margin * 100) should treat nil/zero like closed: show "—" for ROI; unrealized PnL may still be computable from price and side. **Acceptance:** Define behavior when margin_used or open_quantity is nil/zero. |
| **Exchange without ticker** | Future exchange has no public ticker API. | Show "—" for unrealized metrics for that provider/symbol; document that only exchanges with ticker support show unrealized. |
| **Sort order with open rows** | Current sort: `close_at` desc (open rows use last fill time). | Open positions sort by "last activity" time; mixed with closed. **Gap:** Spec says "Filters (Open/Closed) are out of scope" but does not specify if open rows must appear in a specific order (e.g. always at top). Assume current order (close_at desc) is acceptable unless product says otherwise. |
| **Balance for open rows** | `assign_balance!` gives each row a running balance. For open rows, `net_pl` is realized so far (often 0). | Balance = initial_balance + sum(net_pl) of that row and all "below" in list. So open row’s balance is the balance after the previous (newer) positions. **Gap:** Spec does not say whether open rows show this same balance or "—" or "n/a". Recommend: show same running balance for consistency (or explicitly accept "balance after this row in list order"). |

---

## 3. Missing Specs (Gaps)

### 3.1 Balance for open rows

- **Gap:** No definition of what to show in the Balance column for open positions.
- **Current behavior:** `assign_balance!` runs over all positions; open rows get a balance = initial_balance + cumulative net_pl (from that row and below). For a purely open position, `net_pl` is often 0 (or fees only), so balance is the same as "balance after the previous row."
- **Options:** (A) Show this running balance (consistent with closed). (B) Show "—" for open. (C) Show "running balance as of this row" with a tooltip. **Recommendation:** (A) and add acceptance criterion: "Open rows display the same running balance as closed rows (balance after this position in sort order)."

### 3.2 Sorting

- **Gap:** Sort order is not explicitly specified for the mixed open/closed list.
- **Current behavior:** `PositionSummary.from_trades` sorts by `close_at` desc (open rows use last trade’s `executed_at` as `close_at`). So newest-first by "close or last activity."
- **Recommendation:** Add: "Positions are ordered by close_at descending (open positions use last fill time). No separate sort for open vs closed in this iteration."

### 3.3 Error handling (ticker)

- **Gap:** Exact behavior when ticker fails is only loosely specified ("price unavailable → show —").
- **To specify:** (1) Timeout and retry: no retry / one retry / fail silently per symbol. (2) Logging: log warning vs silent. (3) 429 rate limit: do we skip ticker for all or only for that symbol? **Recommendation:** "On ticker failure (network, 4xx/5xx, timeout): do not retry in this iteration; set current_price to nil for that symbol; log at warning level; render '—' for unrealized PnL/ROI for positions with that symbol."

### 3.4 Price fetch scope and pagination

- **Gap:** When we have 100 positions and 10 are open (spread across pages), do we fetch ticker for all 10 open symbols on first load, or only for open positions on the current page?
- **Options:** (A) Fetch for all open positions in the full result set (so every page has prices for its open rows without a second request). (B) Fetch only for open positions on the current page (fewer API calls when user stays on page 1; page 2 would need either no unrealized or a separate fetch). **Recommendation:** (A) so that "on page load" means one ticker round per symbol for all open positions; pagination is client-side over already-built positions, and open rows on page 2 already have prices. Add acceptance criterion to that effect.

### 3.5 Unrealized formula and edge values

- **Gap:** Unrealized PnL formula (direction-aware: long vs short) and unrealized ROI (unrealized_pnl / margin_used * 100) are implied but not written.
- **To specify:** (1) Unrealized PnL = (current_price - open_avg_price) * open_quantity for long; (open_avg_price - current_price) * open_quantity for short (or equivalent with notional). (2) If margin_used is nil or 0, unrealized ROI = "—". (3) If open_quantity is 0, unrealized PnL = "—". **Recommendation:** Add a short "Formulas" subsection: unrealized PnL and unrealized ROI, and when each shows "—".

### 3.6 Visual distinction for open rows

- **Gap:** Spec says "visually distinguished (e.g. 'Open' in the date column or a badge)" but does not lock the exact treatment.
- **Recommendation:** Add: "Open rows show 'Open' (or equivalent badge) in the Closed column; closed rows show the close date. No other mandatory styling; optional row background or icon is implementation choice."

### 3.7 Partial closes (open quantity after some legs closed)

- **Gap:** Current code does not produce a separate "open" row for the remaining quantity after partial closes; it only produces one row per closing leg (closed) and one aggregate row when there are no closing legs. So "position with 2 partial closes and still open" yields 2 closed rows only; the open remainder is not a row.
- **Recommendation:** Either (A) accept current behavior for this feature (no row for "remaining open" after partials) and document it, or (B) add a follow-up to introduce a row for remaining open quantity and then apply unrealized PnL there. For this spec, state: "Only positions with no closing leg appear as open rows; positions with at least one closing leg show only closed legs as rows (remaining open quantity is out of scope for this iteration)."

---

## 4. Acceptance Criteria to Add

Suggested additions to the feature spec:

1. **Balance:** Open rows display the same running balance as closed rows (the balance after this position in sort order).
2. **Sorting:** Positions are ordered by `close_at` descending; open positions use last fill time. No separate ordering for open vs closed in this iteration.
3. **Ticker failure:** On ticker failure (network, 4xx/5xx, timeout): do not retry; set current_price to nil for that symbol; log at warning level; show "—" for unrealized PnL and unrealized ROI for positions with that symbol. Page load does not fail.
4. **Ticker scope:** Current price is fetched for every unique symbol that has at least one open position in the full index result set (before pagination), so all pages show unrealized metrics for open rows without an extra request when changing pages.
5. **Unrealized formulas:**  
   - Unrealized PnL: direction-aware (long: (current_price - open_avg_price) * open_quantity; short: (open_avg_price - current_price) * open_quantity), or equivalent using existing notional/margin logic. Show "—" if open_quantity or current_price is missing.  
   - Unrealized ROI: (unrealized_pnl / margin_used) * 100 when margin_used present and non-zero; otherwise "—".
6. **Open identification:** A row is "open" if and only if it has no closing leg (built via `build_one_aggregate` with `closing.empty?`). Such rows show "Open" (or badge) in the Closed column and use current price for unrealized PnL/ROI when available.
7. **No open positions:** When there are zero open positions, no ticker API calls are made.
8. **Partial closes:** Only positions with no closing leg are shown as open rows; remaining open quantity after partial closes is out of scope for this feature.

---

## 5. Flow Permutation Summary

| Dimension        | Variants |
|-----------------|----------|
| View            | History (all time) vs Portfolio (date range) |
| Open count      | 0 open, 1 open, many open, same symbol multiple |
| Ticker outcome  | All succeed, all fail, partial success |
| Pagination      | Single page vs multiple pages with open on page 2+ |
| Data edge       | margin_used nil, open_quantity 0, single-fill "open" |

---

## 6. Critical Questions for Product

1. **Balance for open rows:** Show running balance (same as today’s formula) or "—" / "n/a"? (Recommendation: running balance.)
2. **Price fetch scope:** Fetch ticker for all open positions (full result set) or only for the current page? (Recommendation: full set so pagination doesn’t need a second fetch.)
3. **Partial closes:** Is it in scope to show a row for "remaining open quantity" after some legs are closed? (Recommendation: no for this iteration; document as out of scope.)

---

## 7. Recommended Next Steps

1. Confirm or add the acceptance criteria above to the brainstorm/plan.
2. Implement `open?` (or equivalent) on `PositionSummary` (e.g. no closing leg in `trades`).
3. Introduce a ticker fetcher (e.g. BingX public ticker by symbol), called from the index service (or a decorator) with the list of unique symbols from open positions; return a hash symbol → price (or nil).
4. Add unrealized PnL and unrealized ROI to `PositionSummary` (or view helper) when `current_price` and open data present; otherwise "—".
5. Update trades index view: Closed column shows "Open" or date; ROI/Net PnL for open rows use unrealized when price present.
6. Add tests: no ticker call when zero open; "—" when ticker fails; partial ticker success; balance and sort behavior for open rows.
