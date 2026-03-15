# P2: SyncService updates last_synced_at before RebuildForAccountService

**Status:** complete  
**Priority:** p2  
**Tags:** code-review, reliability, sync

## Problem Statement

In `ExchangeAccounts::SyncService#call`, `SyncRun` is created and `last_synced_at` is updated (lines 26–27) **before** `Positions::RebuildForAccountService.call(@account)` (line 28). If Rebuild raises (e.g. bug, timeout, DB issue), the account is left with trades persisted and "synced" state, but positions not rebuilt—stale or inconsistent positions until next successful sync.

## Findings

- **Location:** `app/services/exchange_accounts/sync_service.rb` (lines 24–30).
- **Current order:** persist trades → create SyncRun → update last_synced_at → Rebuild positions.
- **Risk:** Rebuild failure leaves last_synced_at set; next sync may use incremental window and never retry the failed rebuild for that batch; positions can remain out of date.

## Proposed Solutions

1. **Move Rebuild before SyncRun/last_synced_at**  
   Call `Positions::RebuildForAccountService.call(@account)` immediately after `trades.each { |attrs| persist_trade(attrs) }`; only then create SyncRun and update last_synced_at.  
   **Pros:** last_synced_at only advances when positions are consistent. **Cons:** Rebuild failure causes full sync to "fail" (job may retry, good). **Effort:** Small.

2. **Rescue Rebuild and skip last_synced_at on failure**  
   Wrap Rebuild in begin/rescue; only update SyncRun and last_synced_at if Rebuild succeeds.  
   **Pros:** Same consistency as (1). **Cons:** Slightly more code. **Effort:** Small.

3. **Leave as-is and document**  
   Accept that a failed Rebuild leaves stale positions until next run; document in the class.  
   **Pros:** No change. **Cons:** Operational confusion when positions are wrong but "last synced" is recent. **Effort:** Tiny.

**Recommended:** Option 1 (Rebuild before marking sync complete).

## Acceptance Criteria

- [x] SyncRun is created and last_synced_at is updated only after Positions::RebuildForAccountService completes successfully (or move Rebuild before those two steps).
- [x] If Rebuild raises, the job fails and can retry without having advanced last_synced_at.
- [x] Existing tests still pass; optionally add a test that when Rebuild raises, last_synced_at is not updated.

## Work Log

- Moved `Positions::RebuildForAccountService.call(@account)` before `SyncRun.create!` and `@account.update_column(:last_synced_at, ...)` so last_synced_at only advances when positions are rebuilt. Updated class comment.

## Resources

- `app/services/exchange_accounts/sync_service.rb`
- `test/jobs/sync_exchange_account_job_test.rb`
