---
status: pending
priority: p1
issue_id: "016"
tags: [code-review, architecture, dry, exchange-clients]
dependencies: []
---

# Duplicate `allowed_quote?` method in BinanceClient and BingxClient

## Problem Statement

`allowed_quote?` is copy-pasted verbatim into both `BinanceClient` (lines 90–95) and `BingxClient` (lines 97–102). The method bodies are character-for-character identical. Both clients inherit from `BaseProvider`. Additionally, `BingxClient` keeps a `stablequote_pair?` alias pointing to the same method — the three internal call sites use the alias name, making `BingxClient` use different method names than `BinanceClient` for the same behavior.

If the symbol format convention (`BASE-QUOTE` hyphen separator) ever changes, it must be updated in two places. This is a live divergence risk.

**Flagged as P1 by:** kieran-rails-reviewer, dhh-rails-reviewer, code-simplicity-reviewer, architecture-strategist (all four independently).

## Findings

**`app/services/exchanges/binance_client.rb` lines 88–95:**
```ruby
def allowed_quote?(symbol)
  return true if @allowed_quote_currencies.blank?
  return false if symbol.blank?
  quote = symbol.to_s.split("-").last.to_s.upcase
  @allowed_quote_currencies.include?(quote)
end
```

**`app/services/exchanges/bingx_client.rb` lines 95–104 (+ alias):**
```ruby
def allowed_quote?(symbol)
  return true if @allowed_quote_currencies.blank?
  return false if symbol.blank?
  quote = symbol.to_s.split("-").last.to_s.upcase
  @allowed_quote_currencies.include?(quote)
end

alias stablequote_pair? allowed_quote?
```

Also duplicated: the `DEFAULT_QUOTE_CURRENCIES` constant is re-declared on both clients as an alias for `Exchanges::QuoteCurrencies::DEFAULT`.

## Proposed Solutions

### Option A: Move `allowed_quote?` to `BaseProvider` (Recommended)

Read `app/services/exchanges/base_provider.rb` first to understand current state.

Move `@allowed_quote_currencies` initialization and `allowed_quote?` to `BaseProvider`. Each client's `initialize` calls `super` or sets the ivar via the base. Remove the method from both concrete clients. Remove `stablequote_pair?` alias and update the three call sites in `BingxClient` to use `allowed_quote?` directly. Move `DEFAULT_QUOTE_CURRENCIES` constant to `BaseProvider` and remove from both clients.

**Pros:** Single source of truth, consistent naming, DRY.
**Cons:** Requires `BaseProvider#initialize` to be wired up; need to verify no other subclass or test breaks.
**Effort:** Small
**Risk:** Low — method logic is identical, just moving it

```ruby
# app/services/exchanges/base_provider.rb
module Exchanges
  class BaseProvider
    DEFAULT_QUOTE_CURRENCIES = Exchanges::QuoteCurrencies::DEFAULT

    def initialize(allowed_quote_currencies: DEFAULT_QUOTE_CURRENCIES)
      @allowed_quote_currencies = allowed_quote_currencies.presence || DEFAULT_QUOTE_CURRENCIES
    end

    protected

    def allowed_quote?(symbol)
      return true if @allowed_quote_currencies.blank?
      return false if symbol.blank?
      quote = symbol.to_s.split("-").last.to_s.upcase
      @allowed_quote_currencies.include?(quote)
    end
  end
end
```

Each client's `initialize` passes `allowed_quote_currencies:` via `super` or sets `@allowed_quote_currencies` before calling `super`.

### Option B: Extract a `QuoteFilter` value object

Create `Exchanges::QuoteFilter` that wraps the whitelist and exposes `#allowed?(symbol)`. Both clients hold an instance.

**Pros:** More explicit, testable in isolation.
**Cons:** Extra abstraction for a 5-line method.
**Effort:** Medium
**Risk:** Low

## Recommended Action

Option A. This is a 2-minute change.

## Technical Details

**Files to change:**
- `app/services/exchanges/base_provider.rb` — add `allowed_quote?` and `@allowed_quote_currencies` init
- `app/services/exchanges/binance_client.rb` — remove `allowed_quote?`, remove `DEFAULT_QUOTE_CURRENCIES`, update `initialize` to pass via `super`
- `app/services/exchanges/bingx_client.rb` — remove `allowed_quote?`, remove `DEFAULT_QUOTE_CURRENCIES`, remove `alias stablequote_pair?`, update 3 internal call sites (lines 116, 150, 175) to call `allowed_quote?`

**Tests to verify unchanged behavior:**
- `test/services/exchanges/binance_client_test.rb` — existing whitelist tests
- `test/services/exchanges/bingx_client_test.rb` — existing whitelist tests

## Acceptance Criteria

- [ ] `allowed_quote?` defined exactly once, in `BaseProvider`
- [ ] `stablequote_pair?` alias removed from `BingxClient`
- [ ] BingxClient internal call sites use `allowed_quote?` (lines 116, 150, 175)
- [ ] `DEFAULT_QUOTE_CURRENCIES` declared once, in `BaseProvider`
- [ ] All existing whitelist tests pass without modification

## Work Log

- 2026-03-19: Flagged as P1 by 4 independent review agents during /ce:review of PR #25

## Resources

- PR #25: feat(exchange-accounts): per-account quote currency whitelist with USDC support
- Related: todo 015 (schema drift) should be fixed in the same PR push
