---
status: complete
priority: p3
issue_id: "028"
tags: [code-review, quality, rails]
dependencies: []
---

# Remove Redundant `buckets.any?` Guard Around Style Block in allocations/show.html.erb

## Problem Statement

`allocations/show.html.erb` wraps the `<style>` block in `<% if @summary.buckets.any? %>`. An empty `<style>` tag with zero rules is perfectly harmless — browsers ignore it. The guard adds a conditional branch for zero benefit. The dashboard view does not have this guard and is the simpler, correct pattern.

## Findings

- `app/views/allocations/show.html.erb:1` — `<% if @summary.buckets.any? %>` wraps the style block
- `app/views/allocations/show.html.erb:8` — matching `<% end %>`
- `app/views/dashboards/show.html.erb:193` — no guard present; the style block is inside `if @allocation_summary.buckets.any?` for the whole allocation section already
- An empty `<style nonce="..."></style>` generates ~40 bytes of HTML and zero CSS rules — no behavioral difference

## Proposed Solutions

### Option 1: Remove the guard, keep the style block unconditional

```erb
<style nonce="<%= content_security_policy_nonce %>">
  <% @summary.buckets.each do |b| %>
    .bc-<%= b.id %> { background: <%= b.color %>; }
    .bl-<%= b.id %> { border-left: 4px solid <%= b.color %>; }
  <% end %>
</style>
```

**Effort:** 2 minutes
**Risk:** None

## Recommended Action

Remove the `if @summary.buckets.any?` / `end` wrapper. If todo 025 (extract to partial) is done, this becomes moot as the partial handles its own rendering.

## Technical Details

**Affected files:**
- `app/views/allocations/show.html.erb` — remove wrapper conditional

## Acceptance Criteria

- [ ] No `if @summary.buckets.any?` guard around the style block
- [ ] Page renders correctly with and without buckets

## Work Log

### 2026-04-21 - Discovered during code review

**By:** Claude Code (code-simplicity-reviewer agent)
