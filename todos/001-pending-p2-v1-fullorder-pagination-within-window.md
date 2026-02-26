# P2: v1 fullOrder pagination within 7-day window

**Status:** complete  
**Priority:** p2  
**Tags:** code-review, performance, rails, bingx

## Problem Statement

When fetching trades via BingX v1 `fullOrder`, the client iterates in 7-day windows and requests up to 500 orders per window. If a single 7-day window contains **more than 500 FILLED orders**, only the first 500 are processed; the loop then advances `start_time` to the next window and never requests the remainder in the same window. Active traders can exceed 500 fills in a week, leading to missing trades.

## Findings

- **Location:** `app/services/exchanges/bingx_client.rb`, `fetch_trades_from_v1_full_order`
- After processing `orders`, the code does `start_time = window_end + 1` and `break if orders.size < limit`. When `orders.size == 500`, we do not break, so we move to the next window and never paginate within the current window.
- BingX v1 fullOrder supports an optional `orderId` parameter: "Only return subsequent orders, and return the latest order by default" — so we can paginate within the same window by passing the last `orderId` (or similar) for the next request.

## Proposed Solutions

1. **Paginate within window by orderId (recommended):** In the inner loop, when `orders.size == limit`, fetch the minimum `orderId` from the batch, then make another request for the same `startTime`/`endTime` with `orderId` set so the API returns the next batch. Continue until we get fewer than `limit` orders. Then advance to the next 7-day window.  
   - *Pros:* Correctness for high-volume accounts.  
   - *Cons:* Need to confirm BingX semantics for `orderId` (subsequent vs previous).  
   - *Effort:* Medium.

2. **Document as known limitation:** Add a comment and/or config max history (e.g. "last 7 days only" or "first 500 orders per week").  
   - *Pros:* No code change.  
   - *Cons:* Silent data loss for power users.  
   - *Effort:* Small.

3. **Use smaller windows:** Use 1-day windows so 500 orders/day is a higher bar.  
   - *Pros:* Reduces chance of hitting the cap.  
   - *Cons:* More API calls; still possible to miss if >500 in a day.  
   - *Effort:* Small.

## Recommended Action

Implement solution 1 (paginate within window) after confirming BingX v1 fullOrder `orderId` behavior from the docs.

## Technical Details

- **Affected:** `Exchanges::BingxClient#fetch_trades_from_v1_full_order`
- **API:** `GET /openApi/swap/v1/trade/fullOrder` with `startTime`, `endTime`, `limit` (max 1000 per docs; code uses 500).

## Acceptance Criteria

- [ ] For a 7-day window that has >500 FILLED orders, all such orders are fetched and normalized (or documented cap).
- [ ] No regression for accounts with <500 fills per week.
- [ ] Unit or integration test covering pagination within one window (optional).

## Work Log

- 2026-02-26: Code review – finding created.
- 2026-02-26: Add inner loop in fetch_trades_from_v1_full_order: when orders.size == limit, pass min orderId as `orderId` param and request again within same window until orders.size < limit. Then advance to next 7-day window.
