---
status: pending
priority: p2
issue_id: "017"
tags: [code-review, quality, exchange-accounts, model]
dependencies: ["016"]
---

# Extract private `raw_allowed_quote_currencies` helper in ExchangeAccount

## Problem Statement

`app/models/exchange_account.rb` contains four copies of the same defensive JSONB read:

```ruby
settings.is_a?(Hash) ? settings["allowed_quote_currencies"] : nil
```

This appears in:
- The custom getter (line 12)
- `normalize_allowed_quote_currencies` (line 48)
- `allowed_quote_currencies_is_array` (line 54)
- `allowed_quote_currencies_are_valid` (line 59)

If the settings key is ever renamed, or if the type guard changes (e.g., adding support for `ActionController::Parameters`), all four copies must be updated.

## Proposed Solutions

### Option A: Extract private `raw_stored_currencies` helper (Recommended)

```ruby
private

def raw_stored_currencies
  settings.is_a?(Hash) ? settings["allowed_quote_currencies"] : nil
end
```

Then simplify all four call sites to `raw = raw_stored_currencies`.

**Pros:** Single place to change if key or guard logic evolves. Removes ~12 lines of duplication.
**Effort:** Small
**Risk:** Low

### Option B: Leave as-is

**Pros:** No change needed.
**Cons:** Four-way duplication grows if more validations are added.
**Effort:** None
**Risk:** Maintenance debt

## Recommended Action

Option A. Small cleanup, low risk.

## Technical Details

**Files to change:**
- `app/models/exchange_account.rb`

## Acceptance Criteria

- [ ] The `settings.is_a?(Hash) ? settings["allowed_quote_currencies"] : nil` expression appears at most once (inside the helper)
- [ ] All four existing tests still pass

## Work Log

- 2026-03-19: Flagged by kieran-rails-reviewer, code-simplicity-reviewer, architecture-strategist, performance-oracle during /ce:review of PR #25
