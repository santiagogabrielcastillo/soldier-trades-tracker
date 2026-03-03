# TickerFetcher: log warning when HTTP response is not 200

- **status:** complete
- **priority:** p2
- **issue_id:** 010
- **tags:** code-review, rails, observability
- **dependencies:** none

## Problem Statement

When BingX ticker returns a non-200 response (e.g. 4xx invalid symbol, 5xx server error), `TickerFetcher#fetch_one` returns `nil` and the symbol is omitted from the result. The plan specified: "If the ticker request fails for a symbol, ... log a warning." Timeouts and `JSON::ParserError` are already logged; HTTP error status codes are not, so ops have no visibility when the exchange returns an error.

## Findings

- **Location:** `app/services/exchanges/bingx/ticker_fetcher.rb`, `fetch_one` method (lines 34–55).
- **Current behavior:** `return nil unless res.code.to_s == "200"` — no log before returning.
- **Impact:** Harder to debug "why is this symbol showing —?" when the cause is 400/404/500 from BingX.

## Proposed Solutions

1. **Log before return (recommended)**  
   Before `return nil unless res.code.to_s == "200"`, add:  
   `Rails.logger.warn("[TickerFetcher] HTTP #{res.code} for #{symbol}: #{res.body.to_s[0..200]}")`  
   **Pros:** Simple, consistent with existing timeout/parse logs. **Cons:** None. **Effort:** Small. **Risk:** Low.

2. **Log only for 5xx**  
   Log only when `res.code.to_s.start_with?("5")` to reduce noise from client errors.  
   **Pros:** Less log volume. **Cons:** 4xx (e.g. invalid symbol) still silent. **Effort:** Small. **Risk:** Low.

3. **Leave as-is**  
   Rely on timeout/parse logs only.  
   **Pros:** No change. **Cons:** Plan called for logging on failure; non-200 is a failure. **Effort:** None. **Risk:** None.

## Recommended Action

Implement Solution 1: log warning with status and body snippet when `res.code != "200"`.

## Technical Details

- **Affected files:** `app/services/exchanges/bingx/ticker_fetcher.rb`
- **Tests:** Add a test that stubs a 500 response and asserts that a warning is logged (or that `fetch_prices` still returns {} for that symbol and other symbols succeed).

## Acceptance Criteria

- [ ] When ticker GET returns non-200, a warning is logged including symbol and status (and optionally body snippet).
- [ ] Behavior unchanged: that symbol is still omitted from the returned hash; page still renders with "—" for that symbol.

## Work Log

- 2026-03-03: Finding from /review of feat/open-trades-unrealized-pnl branch.
- 2026-03-03: Implemented: log warning with HTTP status and body snippet when res.code != "200" in TickerFetcher#fetch_one.

## Resources

- Plan: docs/plans/2026-03-03-feat-open-trades-unrealized-pnl-plan.md (Ticker failure acceptance criterion)
- Implementation: app/services/exchanges/bingx/ticker_fetcher.rb
