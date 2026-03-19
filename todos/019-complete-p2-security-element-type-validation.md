---
status: pending
priority: p2
issue_id: "019"
tags: [code-review, security, exchange-accounts, validation]
dependencies: []
---

# ExchangeAccount normalization does not validate array element types before calling `.to_s`

## Problem Statement

`normalize_allowed_quote_currencies` calls `.to_s.strip.upcase` on each array element without first checking that elements are strings. If a non-string value (nested Array, Hash, Integer) is written directly to `settings` (bypassing validations via `update_column` or a future console operation), the normalization silently converts it via `to_s`:

- `["USDT", ["USDC"]]` → `["USDT", '["USDC"]']` — the nested array becomes a string, fails the whitelist check, but the error message exposes the stringified internal value
- `["USDT", { foo: "bar" }]` → `["USDT", "{foo: \"bar\"}"]` — same issue

The validation will ultimately reject these values, but the error message `contains unknown currencies: ["USDC"]` leaks the internal representation of the malformed value. In a future UI context, this could expose unexpected data shapes to end users.

Additionally, the fail-open behavior in `allowed_quote?` (returning `true` when `@allowed_quote_currencies.blank?`) is a latent risk — if a client is instantiated without going through the constructor's `.presence || DEFAULT` guard (e.g., a test double, a future subclass), it would pass all symbols through unfiltered.

## Proposed Solutions

### Option A: Add element type guard to normalizer + flip fail-open to fail-closed (Recommended)

**In `normalize_allowed_quote_currencies`:**
```ruby
def normalize_allowed_quote_currencies
  raw = raw_stored_currencies   # use helper from todo #017
  return unless raw.is_a?(Array)
  return unless raw.all? { |el| el.is_a?(String) || el.is_a?(Symbol) }
  self.allowed_quote_currencies = raw.map { _1.to_s.strip.upcase }.uniq
end
```

**In `allowed_quote?` on BaseProvider (after todo #016 is resolved):**
```ruby
def allowed_quote?(symbol)
  return false if @allowed_quote_currencies.blank?   # fail-closed, not fail-open
  return false if symbol.blank?
  quote = symbol.to_s.split("-").last.to_s.upcase
  @allowed_quote_currencies.include?(quote)
end
```

**Pros:** Prevents unexpected coercion; fail-closed is safer for a financial filter.
**Cons:** None of significance.
**Effort:** Small
**Risk:** Low — the `.presence || DEFAULT` guard in `initialize` means the fail-closed change has no effect on the normal code path

### Option B: Add a separate validation method for element types

```ruby
def allowed_quote_currencies_elements_are_strings
  raw = raw_stored_currencies
  return unless raw.is_a?(Array)
  unless raw.all? { |el| el.is_a?(String) || el.is_a?(Symbol) }
    errors.add(:allowed_quote_currencies, "must contain only strings")
  end
end
```

**Pros:** Explicit error message.
**Cons:** Duplicate guard with Option A's normalizer change.
**Effort:** Small

## Recommended Action

Option A for both the normalizer and the fail-closed change. Combine with todo #017 (extract helper).

## Technical Details

**Files:**
- `app/models/exchange_account.rb` — normalizer guard
- `app/services/exchanges/base_provider.rb` — fail-closed (after todo #016)

## Acceptance Criteria

- [ ] `normalize_allowed_quote_currencies` does not call `.to_s` on non-string/symbol elements
- [ ] `allowed_quote?` returns `false` (not `true`) when `@allowed_quote_currencies` is blank
- [ ] Existing tests pass
- [ ] A test covering a nested-array value in settings does not cause normalization to produce a stringified bracket string

## Work Log

- 2026-03-19: Flagged as P2 by security-sentinel during /ce:review of PR #25
