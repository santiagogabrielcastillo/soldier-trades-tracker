# P2: Shared "trades → positions with balance" flow

**Status:** complete  
**Priority:** p2  
**Tags:** code-review, quality, rails, dry

## Problem Statement

`Trades::IndexService` and `Dashboards::SummaryService` duplicate the same pipeline: load trades → `PositionSummary.from_trades(trades)` → `PositionSummary.assign_balance!(positions, initial_balance: …)`. Extracting a shared helper would reduce duplication and keep behavior consistent.

## Findings

- **Location:** `Trades::IndexService#call` (lines 19–22); `Dashboards::SummaryService#portfolio_summary` (lines 27–29), `#all_time_summary` (lines 44–46)
- Same three steps in each place; only the trade relation and optional `initial_balance` differ.

## Proposed Solutions

1. **`PositionSummary.from_trades_with_balance(trades, initial_balance: nil)`:** Add a class method that runs `from_trades` then `assign_balance!` and returns positions. Both services call this with their loaded trades and optional portfolio initial_balance.  
   - *Pros:* Single place for the pipeline; clear name.  
   - *Cons:* PositionSummary gains a dependency on the “balance” concept it already has via assign_balance!.  
   - *Effort:* Small.

2. **Shared concern or private helper in a module:** Extract a module used by both services that implements `build_positions_from_trades(trades, initial_balance: nil)`.  
   - *Pros:* Keeps PositionSummary unchanged.  
   - *Cons:* Extra module and indirection.  
   - *Effort:* Small.

3. **Leave as-is:** Accept the duplication until a third caller appears.  
   - *Pros:* No change.  
   - *Cons:* Same pipeline in two places.  
   - *Effort:* None.

## Recommended Action

(To be filled during triage.)

## Technical Details

- **Affected:** `app/models/position_summary.rb` (if option 1), or new module + `app/services/trades/index_service.rb`, `app/services/dashboards/summary_service.rb`
- **Acceptance criteria:** No duplicated pipeline; both index and dashboard summaries behave the same; tests pass.

## Work Log

- 2026-02-26: Added from code review (feat/codebase-refactor-conventions).
- 2026-02-26: Implemented: added `PositionSummary.from_trades_with_balance(trades, initial_balance: nil)`; `Trades::IndexService` and `Dashboards::SummaryService` use it. Tests pass.
