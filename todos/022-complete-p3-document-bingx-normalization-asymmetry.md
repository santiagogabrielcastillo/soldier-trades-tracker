---
status: pending
priority: p3
issue_id: "022"
tags: [code-review, documentation, exchange-clients, bingx]
dependencies: []
---

# Document BingX/Binance normalization asymmetry in QuoteCurrencies module

## Problem Statement

`Exchanges::QuoteCurrencies::SUPPORTED` is used by `Binance::TradeNormalizer#normalize_symbol` to insert the hyphen separator (e.g., `BTCUSDC` → `BTC-USDC`). This works because Binance returns symbols without a separator.

BingX is different: its `TradeNormalizer` receives symbols that are **already hyphen-formatted** from the exchange API. It does not call `normalize_symbol` and does not need `SUPPORTED` for symbol formatting.

This asymmetry is undocumented in `quote_currencies.rb`. A developer adding a new currency to `SUPPORTED` might assume it "just works" for both exchanges, when in fact they need to verify the BingX normalizer independently.

## Proposed Solutions

### Option A: Add a comment to `quote_currencies.rb` (Recommended)

```ruby
module Exchanges
  # Stablecoin quote currencies recognized across all exchange clients and the trade normalizer.
  #
  # IMPORTANT: Adding a new currency here has different effects per exchange:
  # - Binance: Binance::TradeNormalizer#normalize_symbol uses SUPPORTED to format symbols
  #   (e.g., BTCUSDC → BTC-USDC). Adding a currency here enables Binance symbol formatting.
  # - BingX: BingX returns symbols pre-hyphenated from the API. Bingx::TradeNormalizer
  #   does NOT use SUPPORTED for formatting. Verify BingX compatibility separately.
  module QuoteCurrencies
    SUPPORTED = %w[USDT USDC BUSD].freeze
    DEFAULT = %w[USDT USDC].freeze
  end
end
```

**Effort:** Tiny
**Risk:** None

## Recommended Action

Option A.

## Technical Details

**File:** `app/services/exchanges/quote_currencies.rb`

## Acceptance Criteria

- [ ] `quote_currencies.rb` has a comment explaining the Binance vs BingX normalization difference
- [ ] The comment is accurate (verified against `Binance::TradeNormalizer` and `Bingx::TradeNormalizer`)

## Work Log

- 2026-03-19: Flagged as P2 by architecture-strategist during /ce:review of PR #25
