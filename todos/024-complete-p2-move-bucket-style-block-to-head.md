---
status: complete
priority: p2
issue_id: "024"
tags: [code-review, performance, rails, frontend]
dependencies: []
---

# Move Nonce Style Blocks to `<head>` via `content_for`

## Problem Statement

The `<style nonce="...">` blocks for bucket colors are placed inline in the view body in both `allocations/show.html.erb` and `dashboards/show.html.erb`. A `<style>` element in `<body>` is invalid per HTML spec and forces the browser to perform a mid-parse style recalculation. On slower connections this can cause a brief flash of unstyled content (color dots appearing without color) before the style block is parsed.

## Findings

- `app/views/allocations/show.html.erb:1-8` — `<style>` block at top of view body, before the elements it styles
- `app/views/dashboards/show.html.erb:194-198` — same placement
- Elements using `.bc-{id}` and `.bl-{id}` classes appear later in the DOM — if browser parses them before the `<style>` block, dots render without color briefly
- `content_for :head` exists in the Rails layout and is the correct mechanism to inject per-view styles into `<head>`

## Proposed Solutions

### Option 1: `content_for :head` (recommended)

**Approach:** Wrap the `<style>` block in `content_for :head` in each view.

```erb
<% content_for :head do %>
  <style nonce="<%= content_security_policy_nonce %>">
    <% @summary.buckets.each do |b| %>
      .bc-<%= b.id %> { background: <%= b.color %>; }
      .bl-<%= b.id %> { border-left: 4px solid <%= b.color %>; }
    <% end %>
  </style>
<% end %>
```

Requires the layout to have `<%= yield :head %>` inside `<head>`. Verify this is already present.

**Pros:**
- Spec-compliant placement
- Eliminates mid-body style recalculation
- No flash of unstyled content

**Cons:**
- Requires confirming layout has `yield :head`

**Effort:** 15 minutes
**Risk:** Low

---

### Option 2: Leave as-is (accepted trade-off)

**Approach:** Document the placement as intentional given browser compatibility.

**Pros:** No code change needed
**Cons:** Flash of unstyled content risk on slow connections; technically invalid HTML

**Effort:** 0
**Risk:** Low

## Recommended Action

Check if the layout already has `yield :head`. If yes, move both `<style>` blocks there — it is a 5-minute change. If not, add `yield :head` to the layout first (also small).

## Technical Details

**Affected files:**
- `app/views/allocations/show.html.erb`
- `app/views/dashboards/show.html.erb`
- `app/views/layouts/application.html.erb` — verify `yield :head` exists

## Acceptance Criteria

- [ ] `<style>` blocks render inside `<head>` in the browser
- [ ] Color dots and bucket borders display correctly without flash
- [ ] CSP nonce still applies (nonce on `<style>` tag in `<head>`)

## Work Log

### 2026-04-21 - Discovered during code review

**By:** Claude Code (performance-oracle + architecture-strategist agents)
