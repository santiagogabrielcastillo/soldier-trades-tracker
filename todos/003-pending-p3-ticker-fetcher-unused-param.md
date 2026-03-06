# P3: Binance::TickerFetcher#extract_mark_price has unused symbol parameter

---
status: complete
priority: p3
issue_id: "003"
tags: code-review, quality
dependencies: []
---

## Problem Statement

`Exchanges::Binance::TickerFetcher#extract_mark_price(data, symbol)` accepts a second parameter `symbol` that is never used in the method body. This is dead parameter and can confuse readers or linters.

## Findings

- **Location:** `app/services/exchanges/binance/ticker_fetcher.rb` — method `extract_mark_price(data, symbol)`; `symbol` unused.
- **Impact:** Cosmetic; no behavioral effect.

## Proposed Solutions

1. **Remove the parameter**  
   Change signature to `extract_mark_price(data)` and update the call site to pass only `data`.  
   - Pros: Clear, no dead code.  
   - Effort: Small. Risk: None.

2. **Use symbol in logging**  
   If we add logging on parse failure, include `symbol` in the log message.  
   - Pros: Better diagnostics.  
   - Effort: Small. Risk: None.

## Recommended Action

Remove the unused `symbol` parameter (solution 1); optionally add logging that uses symbol if we want better diagnostics (solution 2).

## Technical Details

- **Affected files:** `app/services/exchanges/binance/ticker_fetcher.rb`
- **Database changes:** None

## Acceptance Criteria

- [x] `extract_mark_price` has no unused parameters; call site updated if signature changes.

## Work Log

| Date       | Action |
|------------|--------|
| 2026-03-06 | Finding created from PR #9 review. |
| 2026-03-06 | Removed unused `symbol` parameter from extract_mark_price and updated call to extract_mark_price(data). |

## Resources

- PR: [#9](https://github.com/santiagogabrielcastillo/soldier-trades-tracker/pull/9)
