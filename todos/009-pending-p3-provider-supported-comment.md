# P3: Add comment that supported? is lightweight check

**Status:** complete  
**Priority:** p3  
**Tags:** code-review, documentation, exchanges

## Problem Statement

`Exchanges::ProviderForAccount#supported?` and `#client` both use the registry and credential checks; `supported?` avoids instantiating the client. A one-line comment would clarify that `supported?` is a lightweight eligibility check and `#client` does full resolution.

## Findings

- **Location:** `app/services/exchanges/provider_for_account.rb`
- No security or correctness issue; documentation improvement only.

## Proposed Solutions

1. **Add comment above `#supported?`:** e.g. "Lightweight check: registry + credentials only; does not instantiate the client. Use #client when you need the actual client."  
   - *Pros:* Clear intent for future readers.  
   - *Cons:* None.  
   - *Effort:* Trivial.

2. **Leave as-is.**  
   - *Pros:* No change.  
   - *Cons:* Intent not obvious.  
   - *Effort:* None.

## Recommended Action

(To be filled during triage.)

## Technical Details

- **Affected:** `app/services/exchanges/provider_for_account.rb`
- **Acceptance criteria:** Comment added and accurate.

## Work Log

- 2026-02-26: Added from code review (feat/codebase-refactor-conventions).
- 2026-02-26: Implemented: added comment above `#supported?`: "Lightweight check: registry + credentials only; does not instantiate the client. Use #client when you need the actual client."
