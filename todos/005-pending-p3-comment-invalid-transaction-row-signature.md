# P3: Comment build_invalid_spot_transaction row_signature

**Status:** complete  
**Priority:** p3  
**Tags:** code-review, rails, clarity

## Problem Statement

`build_invalid_spot_transaction` assigns `row_signature: SecureRandom.hex(32)` so that the unsaved `SpotTransaction` passes presence and uniqueness long enough for `validate` to run and populate errors. This is non-obvious and could be mistaken for real data.

## Findings

- **Location:** `app/controllers/spot_controller.rb` (lines 95–108).
- **Purpose:** We need a valid-looking record to run validations and show field errors; we never persist this object, so the random signature is only to satisfy validations.

## Proposed Solutions

1. **Add a one-line comment**  
   Above the `SpotTransaction.new` or next to `row_signature`: e.g. "Temporary signature so validations run; record is not persisted."  
   **Pros:** Clarifies intent. **Cons:** None. **Effort:** Tiny.

2. **Leave as-is**  
   **Pros:** No change. **Cons:** Future readers may wonder. **Effort:** None.

**Recommended:** Option 1.

## Acceptance Criteria

- [x] A short comment in the controller explains that the random row_signature is only for running validations on an unsaved record.

## Work Log

- Added comment above `SpotTransaction.new` in `build_invalid_spot_transaction`: "Temporary signature so validations run; this record is never persisted."
