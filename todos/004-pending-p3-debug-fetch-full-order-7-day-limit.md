# P3: debug_fetch_full_order omits endTime (v1 7-day limit)

**Status:** complete  
**Priority:** p3  
**Tags:** code-review, quality, rails, bingx

## Problem Statement

`debug_fetch_full_order(since:, limit:)` calls the v1 fullOrder endpoint with only `startTime` and `limit`. The BingX v1 API requires the query range to be **≤ 7 days** (error 109400: "the query range is more than seven days"). So when debugging with e.g. `since: 30.days.ago`, the request fails with 109400 and the debug output is confusing.

## Findings

- **Location:** `app/services/exchanges/bingx_client.rb`, `debug_fetch_full_order`
- It passes `"startTime" => since_ms, "limit" => limit` but no `endTime`.
- Production code in `fetch_trades_from_v1_full_order` correctly uses 7-day windows with both `startTime` and `endTime`.

## Proposed Solutions

1. **Compute endTime in debug method:** Set `end_time = [since_ms + 7.days.in_milliseconds - 1, (Time.now.to_f * 1000).to_i].min` and pass `endTime: end_time` so the debug call always stays within the 7-day limit.  
   - *Pros:* Debug works for any `since`; matches API contract.  
   - *Cons:* Debug only shows one 7-day window.  
   - *Effort:* Small.

2. **Document in method comment:** Add a note: "v1 API allows max 7-day range; pass since within the last 7 days or the request will return 109400."  
   - *Pros:* No code change.  
   - *Cons:* Console users still hit 109400 if they pass 30.days.ago.  
   - *Effort:* None.

## Recommended Action

Implement solution 1 so `debug_fetch_full_order` always sends a valid 7-day window (or document clearly and keep as-is).

## Technical Details

- **Affected:** `Exchanges::BingxClient#debug_fetch_full_order`
- **API:** GET /openApi/swap/v1/trade/fullOrder — startTime + endTime required for range ≤ 7 days.

## Acceptance Criteria

- [ ] Calling `client.debug_fetch_full_order(since: 30.days.ago, limit: 100)` does not return code 109400 (either by sending endTime or by documenting that since must be within 7 days).

## Work Log

- 2026-02-26: Code review – finding created.
- 2026-02-26: Compute endTime as [since_ms + 7 days - 1, now_ms].min and pass to v1 fullOrder so debug call always stays within 7-day limit.
