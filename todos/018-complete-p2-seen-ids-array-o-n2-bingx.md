---
status: pending
priority: p2
issue_id: "018"
tags: [code-review, performance, bingx, exchange-clients]
dependencies: []
---

# `seen_ids = []` causes O(n²) deduplication in BingxClient#fetch_trades_from_v1_full_order

## Problem Statement

`app/services/exchanges/bingx_client.rb` uses an Array for deduplication:

```ruby
seen_ids = []
...
next if order_id.blank? || seen_ids.include?(order_id)
seen_ids << order_id
```

`Array#include?` is O(n). With N orders, the total deduplication cost is O(n²). For accounts with thousands of BingX orders (e.g., on first sync after adding USDC or after a long sync gap), this creates measurable CPU overhead.

This is pre-existing code, not introduced by PR #25, but PR #25 increases the relevance because accounts that add a quote currency after their initial sync will re-fetch extended history on the next sync.

## Proposed Solutions

### Option A: Use `Set` (Recommended)

```ruby
seen_ids = Set.new
```

`Set#include?` is O(1). No other changes needed — `Set` supports `<<` and `include?` with the same API as Array.

**Pros:** One-line fix, O(n) total deduplication cost.
**Cons:** None.
**Effort:** Tiny
**Risk:** None — API is identical

### Option B: Use `Hash` as a set

```ruby
seen_ids = {}
...
next if order_id.blank? || seen_ids.key?(order_id)
seen_ids[order_id] = true
```

**Pros:** No require needed (Set is also in stdlib, so this advantage is minimal).
**Cons:** Slightly more verbose than Set.
**Effort:** Tiny
**Risk:** None

## Recommended Action

Option A. `require 'set'` is not needed in modern Ruby (Set is autoloaded since Ruby 3.2; for earlier versions, `Set` is already in the stdlib and typically auto-required by Rails).

## Technical Details

**File:** `app/services/exchanges/bingx_client.rb`, line 128

## Acceptance Criteria

- [ ] `seen_ids` is a `Set`, not an `Array`
- [ ] Existing BingxClient tests pass
- [ ] No behavior change — only the deduplication data structure changes

## Work Log

- 2026-03-19: Flagged as P1 by performance-oracle agent during /ce:review of PR #25 (downgraded to P2 as pre-existing, not introduced by this PR)
