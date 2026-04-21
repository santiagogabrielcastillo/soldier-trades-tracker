---
status: complete
priority: p2
issue_id: "023"
tags: [code-review, security, rails]
dependencies: []
---

# Add Hex Color Format Validation to AllocationBucket

## Problem Statement

`AllocationBucket#color` is interpolated directly into a nonce-protected `<style>` block without sanitization. The only model validation is `presence: true`. A user can bypass the browser's color picker via a direct HTTP request and store a malicious CSS payload, resulting in CSS injection.

## Findings

- `app/models/allocation_bucket.rb` — `validates :color, presence: true` only; no format check
- `app/views/allocations/show.html.erb:4` — `<%= b.color %>` interpolated raw into `<style>` content
- `app/views/dashboards/show.html.erb:196` — same interpolation
- A payload like `red; } body { visibility: hidden } .x {` would render valid CSS inside the nonce-protected block
- The nonce on `<style>` authorizes the block to execute — it does not sanitize the content within it
- Realistic impact is low (authenticated user can only affect their own page) but the pattern is wrong

## Proposed Solutions

### Option 1: Model-layer format validation (recommended)

**Approach:** Add a format validator on `AllocationBucket` that enforces 6-digit hex colors.

```ruby
validates :color, presence: true,
                  format: { with: /\A#[0-9a-fA-F]{6}\z/, message: "must be a valid hex color (e.g. #6366f1)" }
```

**Pros:**
- Single source of truth — validation at the data layer
- Error surfaces in the form before any CSS is generated
- Minimal code change

**Cons:**
- None at this scale

**Effort:** 15 minutes
**Risk:** Low

---

### Option 2: View-layer sanitization only

**Approach:** Sanitize in the ERB: `<%= b.color.gsub(/[^#0-9a-fA-F]/, '') %>` as defense-in-depth.

**Pros:** Catches bad data already in the DB

**Cons:**
- Does not prevent bad data from entering the DB
- Wrong layer for validation

**Effort:** 5 minutes
**Risk:** Low

---

### Option 3: Both (defense-in-depth)

Add model validation AND view sanitization.

**Effort:** 20 minutes
**Risk:** Low

## Recommended Action

Implement Option 1. Add the format validator to the model. Optionally add a migration to clean any existing malformed values.

## Technical Details

**Affected files:**
- `app/models/allocation_bucket.rb` — add format validator
- `test/models/allocation_bucket_test.rb` — add validation tests

## Acceptance Criteria

- [ ] `AllocationBucket` validates color against `/\A#[0-9a-fA-F]{6}\z/`
- [ ] Submitting an invalid color via HTTP returns a validation error
- [ ] Existing tests pass

## Work Log

### 2026-04-21 - Discovered during code review

**By:** Claude Code (security-sentinel agent)

**Actions:**
- Identified CSS injection risk via unvalidated `b.color` interpolated into nonce `<style>` block
- Confirmed `presence: true` is the only existing validation on `AllocationBucket#color`
- Assessed impact as medium (reduced to low given single-user architecture)
