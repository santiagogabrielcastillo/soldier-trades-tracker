# P3: Move position_id into normalizer for provider-agnostic SyncService

**Status:** complete  
**Priority:** p3  
**Tags:** code-review, architecture, exchanges, sync

## Problem Statement

`ExchangeAccounts::SyncService#persist_trade` reads `raw["positionID"]` (BingX-specific key) from `attrs[:raw_payload]`. SyncService is intended to be exchange-agnostic; provider-specific keys should be normalized by the provider’s normalizer so SyncService only sees a generic `attrs[:position_id]`.

## Findings

- **Location:** `app/services/exchange_accounts/sync_service.rb` lines 42–51
- `position_id: raw["positionID"]&.to_s.presence` couples SyncService to BingX payload shape.
- `Bingx::TradeNormalizer` already produces hashes with `raw_payload`; adding `position_id` to the normalized hash (from `raw["positionID"]`) keeps SyncService generic.

## Proposed Solutions

1. **Add position_id to Bingx::TradeNormalizer output:** In each normalizer method, set `position_id: (raw["positionID"] || raw["position_id"])&.to_s.presence` in the returned hash. SyncService uses `attrs[:position_id]` and no longer reads `raw_payload` for position_id.  
   - *Pros:* SyncService stays provider-agnostic; one place for BingX field mapping.  
   - *Cons:* Requires touching all three normalizer methods.  
   - *Effort:* Small.

2. **Leave as-is:** Document that SyncService expects raw_payload to contain positionID for grouping.  
   - *Pros:* No code change.  
   - *Cons:* Leaky abstraction.  
   - *Effort:* None.

## Recommended Action

(To be filled during triage.)

## Technical Details

- **Affected:** `app/services/exchanges/bingx/trade_normalizer.rb`, `app/services/exchange_accounts/sync_service.rb`
- **Acceptance criteria:** SyncService does not reference `raw["positionID"]`; position_id still persisted correctly for BingX; tests pass.

## Work Log

- 2026-02-26: Added from code review (feat/codebase-refactor-conventions).
- 2026-02-26: Implemented: added `position_id` to all three `Bingx::TradeNormalizer` methods (from raw positionID/position_id); SyncService uses `attrs[:position_id]` and no longer reads raw_payload for position_id. Tests pass.
