# P3: Deduplicate @tokens_for_select logic

**Status:** complete  
**Priority:** p3  
**Tags:** code-review, rails, dry

## Problem Statement

The list `@tokens_for_select` (account tokens + `Spot::TokenList::LIST`, uniq, sort) is computed in two places: in `SpotController#index` and inside `load_index_data` (used by `create` when re-rendering index). The logic is duplicated.

## Findings

- **Location:** `app/controllers/spot_controller.rb`: index (lines 17–19) and `load_index_data` (lines 116–117).
- **Current code:** Same two lines in both places. Easy to drift if one is updated and the other is not.

## Proposed Solutions

1. **Extract to private method**  
   e.g. `tokens_for_select_for(spot_account)` that returns `(spot_account.spot_transactions.distinct.pluck(:token) + Spot::TokenList::LIST).uniq.sort`. Call it from both `index` and `load_index_data`.  
   **Pros:** Single source of truth. **Cons:** None. **Effort:** Small.

2. **Leave as-is**  
   Duplication is minimal (two lines).  
   **Pros:** No change. **Cons:** Still duplicated. **Effort:** None.

**Recommended:** Option 1.

## Acceptance Criteria

- [x] One private method (or equivalent) defines the tokens-for-select list.
- [x] Both `index` and `load_index_data` use it.
- [x] Tests unchanged.

## Work Log

- Added private `tokens_for_select_for(spot_account)` returning `(spot_account.spot_transactions.distinct.pluck(:token) + Spot::TokenList::LIST).uniq.sort`. `index` and `load_index_data` now call it.
