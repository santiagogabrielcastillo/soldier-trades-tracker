# P3: Rake deduplicate tasks — dry-run or confirmation

**Status:** pending  
**Priority:** p3  
**Tags:** code-review, rake, operations

## Problem Statement

`trades:deduplicate` and `positions:deduplicate` are destructive (they delete duplicate records). There is no dry-run or confirmation step, so a mistaken run could delete data. For production use, a safety option would reduce operational risk.

## Findings

- **Location:** `lib/tasks/trades.rake`, `lib/tasks/positions.rake`.
- **Current behavior:** Task runs immediately and deletes duplicates; prints count at end.
- **Risk:** Low (duplicates are the target); medium if someone runs the wrong task or on wrong env without checking.

## Proposed Solutions

1. **Add ENV['DRY_RUN'] support**  
   If `ENV['DRY_RUN']=1`, only report what would be deleted (counts and maybe sample IDs), do not destroy.  
   **Pros:** Safe preview. **Cons:** Slight code change. **Effort:** Small.

2. **Add confirmation prompt in production**  
   If `Rails.env.production?`, ask for confirmation (e.g. "About to delete X duplicates. Continue? [y/N]") unless ENV['CONFIRM']=1.  
   **Pros:** Prevents accidental production run. **Cons:** Not ideal for scripts/CI. **Effort:** Small.

3. **Document only**  
   In task desc, note "Destructive. Consider running in console or with a backup first."  
   **Pros:** No code change. **Cons:** No programmatic safety. **Effort:** Tiny.

**Recommended:** Option 1 (dry-run) or Option 3 (document) depending on how often these run.

## Acceptance Criteria

- [ ] Either: (a) DRY_RUN reports would-be deletions without destroying, or (b) task description clearly states destructive and suggests care in production.
- [ ] No change to actual deduplication logic when running for real.

## Work Log

(Leave for implementation.)

## Resources

- `lib/tasks/trades.rake`
- `lib/tasks/positions.rake`
