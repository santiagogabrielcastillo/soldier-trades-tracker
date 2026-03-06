# P3: TradeNormalizer#normalize_symbol returns original casing for unknown pairs

---
status: complete
priority: p3
issue_id: "002"
tags: code-review, quality, consistency
dependencies: []
---

## Problem Statement

In `Exchanges::Binance::TradeNormalizer.normalize_symbol`, when the symbol does not end with USDT, USDC, or BUSD, the method returns the original `symbol` argument. Earlier in the method we normalize to `s = symbol.to_s.strip.upcase`, but for the non-matching case we return `symbol`, so unknown pairs can be stored with mixed or lowercase casing (e.g. `"foobar"`) instead of the upcased form (`"FOOBAR"`), which is inconsistent with the normalized USDT/USDC/BUSD output.

## Findings

- **Location:** `app/services/exchanges/binance/trade_normalizer.rb` line 52: `return "#{base}-#{quote}" if base.present?`; later `symbol` is returned.
- **Impact:** Low; only affects symbols that are not USDT/USDC/BUSD. Most production use will be USDT pairs.

## Proposed Solutions

1. **Return upcased form for unknown pairs**  
   In the non-matching case, return `s` instead of `symbol` so all returned symbols are consistently stripped and upcased.  
   - Pros: Consistent casing.  
   - Cons: None.  
   - Effort: Small. Risk: Low.

2. **Leave as-is**  
   Document that only USDT/USDC/BUSD are normalized; others are passed through.  
   - Pros: No change.  
   - Cons: Inconsistent casing for edge-case symbols.  
   - Effort: None. Risk: Low.

## Recommended Action

Apply solution 1: change the final `symbol` to `s` in `normalize_symbol` (and add a test for an unknown pair returning upcased if desired).

## Technical Details

- **Affected files:** `app/services/exchanges/binance/trade_normalizer.rb`
- **Database changes:** None

## Acceptance Criteria

- [x] When symbol does not match USDT/USDC/BUSD, returned value is `symbol.to_s.strip.upcase` (e.g. `s`), not the original `symbol`.

## Work Log

| Date       | Action |
|------------|--------|
| 2026-03-06 | Finding created from PR #9 review. |
| 2026-03-06 | Changed final return from `symbol` to `s` in normalize_symbol. Added test "normalize_symbol returns upcased symbol for unknown quote pair". |

## Resources

- PR: [#9](https://github.com/santiagogabrielcastillo/soldier-trades-tracker/pull/9)
