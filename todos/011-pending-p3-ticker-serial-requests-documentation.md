# Document or consider ticker serial-request behavior at scale

- **status:** complete
- **priority:** p3
- **issue_id:** 011
- **tags:** code-review, performance, documentation
- **dependencies:** none

## Problem Statement

`TickerFetcher` performs one HTTP GET per unique open symbol, sequentially. For typical use (few open positions) this is acceptable. If a user has many open symbols (e.g. 20+), page load could be slow (e.g. 20 × 2s timeout = 40s worst case). The plan already noted "consider batching or parallel HTTP later"; this todo is to document the trade-off or add a short comment in code so future maintainers know the design.

## Findings

- **Location:** `app/services/exchanges/bingx/ticker_fetcher.rb`, `fetch_prices` (iterates `symbols.each` and calls `fetch_one`).
- **Current behavior:** Serial requests; timeouts 5s open / 10s read per symbol.
- **Impact:** Low for current scope (N usually small). Possible future improvement: batch endpoint if BingX supports it, or parallel requests with a concurrency limit.

## Proposed Solutions

1. **Add a short comment in code (recommended)**  
   Above the `symbols.each` loop, add: "Serial requests; acceptable for typical N (e.g. &lt;10 open symbols). For many symbols, consider batching or parallel requests in a follow-up."  
   **Pros:** No behavior change; documents intent. **Cons:** None. **Effort:** Small. **Risk:** None.

2. **Add a constant and guard**  
   Define e.g. `MAX_SYMBOLS = 20` and log a warning (or skip fetching) if `symbols.size > MAX_SYMBOLS` to cap latency.  
   **Pros:** Prevents accidental long waits. **Cons:** User might see "—" for some symbols; more logic. **Effort:** Medium. **Risk:** Low.

3. **Leave as-is**  
   No comment or guard. **Pros:** No change. **Cons:** Future dev may not know why page is slow with many symbols. **Effort:** None. **Risk:** None.

## Recommended Action

Implement Solution 1: add the one-line comment in `TickerFetcher#fetch_prices`. Optionally add the same note to the plan's "Performance" / "Research insights" section if not already there.

## Technical Details

- **Affected files:** `app/services/exchanges/bingx/ticker_fetcher.rb` (and optionally docs/plans/2026-03-03-feat-open-trades-unrealized-pnl-plan.md)
- **No DB or API change.**

## Acceptance Criteria

- [ ] Code or plan documents that ticker is serial and that batching/parallel could be a follow-up for many symbols.

## Work Log

- 2026-03-03: Finding from /review of feat/open-trades-unrealized-pnl branch.
- 2026-03-03: Implemented: added comment in TickerFetcher#fetch_prices above symbols.each documenting serial requests and future batching/parallel option.

## Resources

- Plan: docs/plans/2026-03-03-feat-open-trades-unrealized-pnl-plan.md (Performance / Research insights)
- Implementation: app/services/exchanges/bingx/ticker_fetcher.rb
