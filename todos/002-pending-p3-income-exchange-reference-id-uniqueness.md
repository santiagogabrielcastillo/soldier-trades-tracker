# P3: Income-derived trade exchange_reference_id uniqueness

**Status:** complete  
**Priority:** p3  
**Tags:** code-review, quality, rails, bingx

## Problem Statement

When trades are derived from the user/income endpoint, `exchange_reference_id` is built as `"income_#{time_ms}_#{index}_#{raw['id'] || raw['tranId']}"`. If the API omits both `id` and `tranId`, the same `time_ms` and `index` can produce identical IDs for different income records (e.g. two entries in the same millisecond), risking unique constraint violations or overwrites when upserting into `trades`.

## Findings

- **Location:** `app/services/exchanges/bingx_client.rb`, `normalize_income_to_trade`
- Line: `exchange_reference_id = "income_#{time_ms}_#{index}_#{raw['id'] || raw['tranId']}"`
- If `raw['id']` and `raw['tranId']` are both nil/blank, the suffix is empty; multiple records with the same `time_ms` and `index` in a batch would only differ by index, but if the API returns duplicate indexes or same timestamp for multiple items, IDs could collide.

## Proposed Solutions

1. **Add a fallback unique suffix:** When `raw['id']` and `raw['tranId']` are blank, append something unique per record, e.g. `SecureRandom.hex(4)` or a hash of `raw.to_json` (or index + symbol + amount).  
   - *Pros:* Guarantees uniqueness.  
   - *Cons:* Non-deterministic if using SecureRandom (re-sync could create new IDs; then we'd need to match by something else or accept duplicates). Prefer deterministic (e.g. digest of symbol+time+amount+index).  
   - *Effort:* Small.

2. **Require id/tranId and skip otherwise:** Return `nil` from `normalize_income_to_trade` when both `id` and `tranId` are missing, so we don't create a trade row for that income record.  
   - *Pros:* Avoids bad IDs.  
   - *Cons:* Drops those income entries.  
   - *Effort:* Small.

3. **Leave as-is and monitor:** Keep current behavior; if BingX always sends id or tranId, no issue. Add a comment.  
   - *Pros:* No change.  
   - *Cons:* Risk remains if API changes.  
   - *Effort:* None.

## Recommended Action

Use a deterministic fallback (e.g. `Digest::SHA256.hexdigest("#{symbol}_#{time_ms}_#{index}_#{amount}")[0..15]`) when `id` and `tranId` are blank, so re-syncs produce the same ID and upserts remain idempotent.

## Technical Details

- **Affected:** `Exchanges::BingxClient#normalize_income_to_trade`
- **Downstream:** `SyncExchangeAccountJob` uses `find_or_initialize_by(exchange_reference_id: attrs[:exchange_reference_id])`; duplicate IDs would cause one record to overwrite the other.

## Acceptance Criteria

- [ ] No two income-derived trades get the same `exchange_reference_id` when both id and tranId are missing.
- [ ] Re-sync produces the same IDs for the same income records (deterministic).

## Work Log

- 2026-02-26: Code review – finding created.
- 2026-02-26: When id/tranId blank, use Digest::SHA256.hexdigest("#{symbol}_#{time_ms}_#{index}_#{amount}")[0..15] for deterministic unique id.
