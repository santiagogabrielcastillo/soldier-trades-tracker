---
status: complete
priority: p2
issue_id: "025"
tags: [code-review, architecture, rails, dry]
dependencies: ["024"]
---

# Extract Bucket Color Style Block to a Shared Partial

## Problem Statement

The nonce `<style>` block that generates `.bc-{id}` and `.bl-{id}` CSS rules is duplicated between `allocations/show.html.erb` and `dashboards/show.html.erb`. If more views reference `@allocation_summary.buckets` (e.g., a future portfolio overview page), the block will need to be copy-pasted a third time. There is no shared partial or helper that encapsulates this concern.

## Findings

- `app/views/allocations/show.html.erb:1-8` — generates `.bc-{id}` and `.bl-{id}` rules
- `app/views/dashboards/show.html.erb:194-198` — generates only `.bc-{id}` rules (subset)
- The two blocks are not identical: allocations needs both `bc` and `bl` rules; dashboard only needs `bc`. A shared partial should accept `include_border: true/false` or always emit both (the unused `.bl-{id}` rules on the dashboard are harmless)
- If 024 (move to `content_for :head`) is done first, extract from there

## Proposed Solutions

### Option 1: Shared partial with all rules (recommended)

**Approach:** Create `app/views/allocations/_bucket_styles.html.erb`:

```erb
<style nonce="<%= content_security_policy_nonce %>">
  <% buckets.each do |b| %>
    .bc-<%= b.id %> { background: <%= b.color %>; }
    .bl-<%= b.id %> { border-left: 4px solid <%= b.color %>; }
  <% end %>
</style>
```

Render with a local: `<%= render "allocations/bucket_styles", buckets: @summary.buckets %>`

Always emit both rules — unused `.bl-{id}` rules are ~20 bytes each and harmless.

**Pros:**
- Single place to update if CSS changes
- New views get the rules by rendering the partial
- Clean interface (takes `buckets` as a local)

**Cons:**
- Minor: always emits `.bl-{id}` even on pages that don't use it

**Effort:** 20 minutes
**Risk:** Low

---

### Option 2: Application helper method

**Approach:** Add a view helper that generates the `<style>` content as a string.

**Pros:** Can be called from any context
**Cons:** Mixing HTML generation into Ruby helpers is less idiomatic Rails; harder to read

**Effort:** 30 minutes
**Risk:** Low

## Recommended Action

Option 1. Extract to `app/views/allocations/_bucket_styles.html.erb` after resolving todo 024 (head placement). Replace both inline blocks with the partial render.

## Technical Details

**Affected files:**
- `app/views/allocations/show.html.erb` — replace style block with partial render
- `app/views/dashboards/show.html.erb` — replace style block with partial render
- `app/views/allocations/_bucket_styles.html.erb` — new partial

## Acceptance Criteria

- [ ] Single `_bucket_styles.html.erb` partial exists
- [ ] Both views render it instead of inline blocks
- [ ] Colors render correctly on both pages
- [ ] No duplicate CSS rules

## Work Log

### 2026-04-21 - Discovered during code review

**By:** Claude Code (architecture-strategist agent)
