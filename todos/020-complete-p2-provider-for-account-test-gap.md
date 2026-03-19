---
status: pending
priority: p2
issue_id: "020"
tags: [code-review, testing, exchange-clients, provider-for-account]
dependencies: ["016"]
---

# ProviderForAccount has no test for allowed_quote_currencies forwarding

## Problem Statement

`ProviderForAccount#client` now passes `allowed_quote_currencies: @account.allowed_quote_currencies` to the client constructor. This is the integration point between the model's setting and the exchange client's filtering behavior — the most important new wiring in PR #25.

However, the existing `ProviderForAccount` tests use bare `OpenStruct` accounts without setting `allowed_quote_currencies`. Ruby's `OpenStruct` returns `nil` for unset attributes, so every existing test silently exercises the `nil`-fallback path (`nil.presence || DEFAULT`) rather than the explicit forwarding path.

This means the forwarding of the new `allowed_quote_currencies` attribute is not covered by any test. A future refactor that accidentally removes the `allowed_quote_currencies:` kwarg from the `client` instantiation would not be caught by the test suite.

## Proposed Solutions

### Option A: Add a forwarding test to ProviderForAccountTest (Recommended)

Find or create `test/services/exchanges/provider_for_account_test.rb`. Add a test that:

1. Creates an OpenStruct account with `allowed_quote_currencies: ["USDT"]`
2. Calls `ProviderForAccount.new(account).client`
3. Asserts the resulting client's `@allowed_quote_currencies` equals `["USDT"]`

Since `@allowed_quote_currencies` is private, use `.instance_variable_get(:@allowed_quote_currencies)` in the test assertion, or verify it indirectly through `allowed_quote?` behavior if that becomes a public/protected method on BaseProvider.

**Effort:** Small
**Risk:** None

### Option B: Test indirectly through fetch behavior

Create a BingxClient or BinanceClient with a `["USDT"]` whitelist and stub signed_get to return a USDC trade; assert the trade is excluded.

**Pros:** Higher-level, tests the full chain.
**Cons:** More setup.
**Effort:** Medium

## Recommended Action

Option A for the unit-level forwarding test; this is a gap about the wiring, not about client behavior (which is already tested).

## Technical Details

**File:** `test/services/exchanges/provider_for_account_test.rb` (create or extend)

## Acceptance Criteria

- [ ] A test verifies that `ProviderForAccount.new(account).client` passes `allowed_quote_currencies` from the account to the client instance
- [ ] A test verifies the `nil` fallback path (account with `allowed_quote_currencies: nil` gets `DEFAULT_QUOTE_CURRENCIES`)

## Work Log

- 2026-03-19: Flagged as P2 by architecture-strategist during /ce:review of PR #25
