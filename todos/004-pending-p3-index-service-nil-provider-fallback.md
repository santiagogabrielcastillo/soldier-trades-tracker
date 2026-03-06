# P3: IndexService uses "bingx" fallback when exchange_account is nil

---
status: complete
priority: p3
issue_id: "004"
tags: code-review, reliability, edge-case
dependencies: []
---

## Problem Statement

In `Trades::IndexService#fetch_current_prices_for_open_positions`, open positions are grouped by `p.exchange_account&.provider_type.to_s.presence || "bingx"`. So when `exchange_account` is nil (e.g. theoretically orphaned trade or missing association), the position is grouped under `"bingx"` and we call Bingx::TickerFetcher for that symbol. That may be wrong if the position actually came from another provider, and it hides the nil account case.

## Findings

- **Location:** `app/services/trades/index_service.rb` line 51: `by_provider = open_positions.group_by { |p| p.exchange_account&.provider_type.to_s.presence || "bingx" }`.
- **Context:** Positions are built from trades that belong to an exchange_account; in normal operation exchange_account should always be present. Nil would imply data inconsistency or a bug elsewhere.
- **Impact:** Low; edge case. If we ever have nil, we silently treat as BingX instead of skipping or logging.

## Proposed Solutions

1. **Skip positions with nil exchange_account**  
   Filter before grouping: `open_positions = open_positions.select { |p| p.exchange_account.present? }` (or reject when nil).  
   - Pros: No wrong provider; no fetch for orphaned data.  
   - Cons: Those positions won’t get current price (acceptable for bad data).  
   - Effort: Small. Risk: Low.

2. **Log when nil and skip**  
   Same as above but add `Rails.logger.warn` when we skip a position due to nil exchange_account.  
   - Pros: Visibility for data issues.  
   - Effort: Small. Risk: Low.

3. **Leave as-is**  
   Rely on referential integrity; document that "bingx" is the fallback.  
   - Pros: No code change.  
   - Cons: Silent wrong behavior if nil ever occurs.  
   - Effort: None. Risk: Low.

## Recommended Action

Option 1 or 2: filter out positions with nil `exchange_account` before grouping, and optionally log when we skip. No need to change the fallback string.

## Technical Details

- **Affected files:** `app/services/trades/index_service.rb`
- **Database changes:** None

## Acceptance Criteria

- [x] Positions with nil exchange_account do not drive ticker fetcher calls (either skipped or handled explicitly).
- [x] Optional: log when a position is skipped due to nil exchange_account.

## Work Log

| Date       | Action |
|------------|--------|
| 2026-03-06 | Finding created from PR #9 review. |
| 2026-03-06 | Filter open positions to those with exchange_account.present? before grouping; log each skipped position with nil exchange_account. |

## Resources

- PR: [#9](https://github.com/santiagogabrielcastillo/soldier-trades-tracker/pull/9)
