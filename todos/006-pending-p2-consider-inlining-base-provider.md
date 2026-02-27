# P2: Consider inlining BaseProvider until second exchange

**Status:** pending  
**Priority:** p2  
**Tags:** code-review, architecture, yagni, rails

## Problem Statement

`Exchanges::BaseProvider` is an abstract base with a single concrete implementation (`BingxClient`). The indirection adds a layer without a second provider; the “contract” could live in BingxClient (or docs) until another exchange is added.

## Findings

- **Location:** `app/services/exchanges/base_provider.rb`; `app/services/exchanges/bingx_client.rb` (inherits BaseProvider)
- Docs and plans reference BaseProvider as the contract for multi-exchange; currently only BingX exists.
- Removing it would simplify the hierarchy; adding a second provider would require reintroducing a shared interface or doc.

## Proposed Solutions

1. **Keep BaseProvider:** Leave as-is for future Binance/other clients.  
   - *Pros:* Clear contract; ready for second provider.  
   - *Cons:* Extra abstraction with one implementation.  
   - *Effort:* None.

2. **Inline contract into BingxClient, remove BaseProvider:** Document the required hash shape in BingxClient or in a shared doc; have `ProviderForAccount` and callers depend on “object that implements fetch_my_trades(since:)”. Reintroduce a base or module when adding a second exchange.  
   - *Pros:* Less indirection; YAGNI.  
   - *Cons:* Need to re-add abstraction when second provider lands.  
   - *Effort:* Small.

3. **Replace with module:** Use a `Exchanges::Provider` module with documented interface instead of inheritance.  
   - *Pros:* Same contract, no empty base class.  
   - *Cons:* Slightly different style; still one implementor.  
   - *Effort:* Small.

## Recommended Action

(To be filled during triage.)

## Technical Details

- **Affected:** `app/services/exchanges/base_provider.rb`, `app/services/exchanges/bingx_client.rb`, any code that types or documents “BaseProvider”
- **Acceptance criteria:** Decision documented; if removed, BingxClient and ProviderForAccount still work; tests pass.

## Work Log

- 2026-02-26: Added from code review (feat/codebase-refactor-conventions).
