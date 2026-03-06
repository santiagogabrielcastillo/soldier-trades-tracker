# P2: Binance 200 + error body yields empty trades instead of retriable failure

---
status: complete
priority: p2
issue_id: "001"
tags: code-review, reliability, rails, exchanges
dependencies: []
---

## Problem Statement

Binance API can return HTTP 200 with a JSON body like `{"code": -2015, "msg": "Invalid API key"}` for auth or parameter errors. The Binance HTTP client returns this parsed Hash to the caller. `BinanceClient` treats any non-Array response as "no data" and returns an empty list (`return [] unless resp.is_a?(Array)`). As a result, sync "succeeds" with 0 trades and a SyncRun is created; the job does not retry and the user gets no indication that the API key is invalid or that the request failed.

## Findings

- **Location:** `app/services/exchanges/binance_client.rb` — `symbols_from_position_risk`, `symbols_from_income`, and `fetch_user_trades_for_symbol` all use `return [] unless resp.is_a?(Array)` or `break unless resp.is_a?(Array)`.
- **Evidence:** Binance docs and common REST patterns: many APIs return 200 with a body that includes a `code` field for application-level errors (e.g. invalid key, rate limit). Our HTTP client only raises for HTTP 4xx/5xx status; it does not inspect the parsed body for `code`.
- **Impact:** Revoked or invalid keys can lead to repeated "successful" syncs with zero trades, making debugging harder and wasting job runs.

## Proposed Solutions

1. **Detect error payload in BinanceClient after each signed_get (recommended)**  
   When `resp.is_a?(Hash)` and `resp["code"]` is present and not zero, raise `Exchanges::ApiError` with the message from `resp["msg"]` or `resp["message"]`. This keeps HTTP client generic and centralizes Binance error handling in one place.  
   - Pros: Clear, retriable, consistent with job’s `retry_on Exchanges::ApiError`.  
   - Cons: Need to apply in 3 places or extract a small helper (e.g. `assert_success!(resp)`).  
   - Effort: Small. Risk: Low.

2. **Detect in HttpClient for Binance only**  
   In `Binance::HttpClient#get`, after parsing JSON, if the body is a Hash with a non-zero `code`, raise `ApiError`.  
   - Pros: Single place; all Binance callers get consistent behavior.  
   - Cons: Ties HTTP layer to Binance response shape.  
   - Effort: Small. Risk: Low.

3. **Leave as-is and document**  
   Rely on ping at link time; document that sync may report success with 0 trades if the key becomes invalid later.  
   - Pros: No code change.  
   - Cons: Poor UX and harder ops debugging.  
   - Effort: None. Risk: Medium (user/ops confusion).

## Recommended Action

Implement solution 1: add a private method in `BinanceClient` (e.g. `check_binance_error!(resp)`) that raises `ApiError` when `resp` is a Hash with a non-zero `code`, and call it after each `signed_get` that expects an array. Optionally add a test that stubs a 200 response with `{"code": -2015, "msg": "Invalid API key"}` and expects `ApiError`.

## Technical Details

- **Affected files:** `app/services/exchanges/binance_client.rb`
- **Components:** Symbol discovery (positionRisk, income), fetch_user_trades_for_symbol
- **Database changes:** None

## Acceptance Criteria

- [x] When Binance returns 200 with body `{"code": <non-zero>, "msg": "..."}`, BinanceClient raises `Exchanges::ApiError` (so the job retries).
- [x] Existing tests still pass; add at least one test that expects ApiError for such a response.

## Work Log

| Date       | Action |
|------------|--------|
| 2026-03-06 | Finding created from PR #9 review. |
| 2026-03-06 | Implemented: added `check_binance_error!(resp)` (class + instance), called after each signed_get in symbols_from_position_risk, symbols_from_income, fetch_user_trades_for_symbol, and in ping. Added test "fetch_my_trades raises ApiError when Binance returns 200 with error body". |

## Resources

- PR: [#9 Feature: Add Binance USDⓈ-M Futures](https://github.com/santiagogabrielcastillo/soldier-trades-tracker/pull/9)
- Binance API often uses HTTP 200 + `code` in body for application errors.
