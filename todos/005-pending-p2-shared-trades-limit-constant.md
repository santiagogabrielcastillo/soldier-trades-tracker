# P2: Shared TRADES_LIMIT constant

**Status:** complete  
**Priority:** p2  
**Tags:** code-review, quality, rails, dry

## Problem Statement

`Trades::IndexService` and `Dashboards::SummaryService` both define `TRADES_LIMIT = 2000` and use the same load pattern (`order(executed_at: :asc).limit(TRADES_LIMIT)`). Duplicated constants and logic increase drift risk if one is changed without the other.

## Findings

- **Location:** `app/services/trades/index_service.rb` line 4; `app/services/dashboards/summary_service.rb` line 4
- Same constant value and identical usage for capping trade load for position summary.

## Proposed Solutions

1. **Extract to `PositionSummary::TRADES_LIMIT`:** Define the constant where it’s consumed (position building). Both services use trades only to build `PositionSummary.from_trades`; the limit is effectively “max trades for summary.”  
   - *Pros:* Single source of truth; name reflects usage.  
   - *Cons:* Couples services to PositionSummary for a constant.  
   - *Effort:* Small.

2. **Extract to `Trades::TRADES_LIMIT` and reuse in Dashboards:** Keep the constant in the Trades namespace and have `Dashboards::SummaryService` reference `Trades::IndexService::TRADES_LIMIT` or a shared `Trades::TRADES_LIMIT`.  
   - *Pros:* Minimal change; one definition.  
   - *Cons:* Dashboards depends on Trades namespace.  
   - *Effort:* Small.

3. **Leave as-is:** Accept duplication until a third consumer appears.  
   - *Pros:* No change.  
   - *Cons:* Risk of inconsistent limits.  
   - *Effort:* None.

## Recommended Action

(To be filled during triage.)

## Technical Details

- **Affected:** `app/services/trades/index_service.rb`, `app/services/dashboards/summary_service.rb`
- **Acceptance criteria:** One shared constant used by both services; tests unchanged.

## Work Log

- 2026-02-26: Added from code review (feat/codebase-refactor-conventions).
- 2026-02-26: Implemented: added `PositionSummary::TRADES_LIMIT = 2000`, removed duplicate from `Trades::IndexService` and `Dashboards::SummaryService`; both use `PositionSummary::TRADES_LIMIT`. Tests pass.
