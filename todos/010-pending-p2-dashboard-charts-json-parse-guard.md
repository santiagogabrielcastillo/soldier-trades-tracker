# P2: Harden dashboard charts controller JSON parse

---
status: complete
priority: p2
issue_id: "010"
tags:
  - code-review
  - quality
  - stimulus
  - javascript
---

## Problem Statement

In `app/javascript/controllers/dashboard_charts_controller.js`, `connect()` calls `JSON.parse(this.valueValue || "{}")` without a try/catch. If the data attribute is corrupted, truncated (e.g. by a proxy or HTML sanitizer), or malformed, `JSON.parse` throws and the controller fails. The user then gets a blank "Performance over time" section or a console error instead of a graceful empty state.

## Findings

- **Location:** `app/javascript/controllers/dashboard_charts_controller.js`, line 11.
- **Current code:** `const data = JSON.parse(this.valueValue || "{}")`
- **Risk:** Uncaught exception prevents charts and empty-state message from rendering; degrades UX and can confuse support.

## Proposed Solutions

### Option A: try/catch with fallback to empty (recommended)

Wrap parse in try/catch; on error, treat as empty data (show "No closed positions yet" for both chart areas).

- **Pros:** Simple, robust, no API change. **Cons:** None. **Effort:** Small. **Risk:** Low.

### Option B: try/catch + console.warn

Same as A but log `console.warn("Dashboard charts: invalid data", e)` for debugging.

- **Pros:** Aids debugging. **Cons:** Slight noise. **Effort:** Small. **Risk:** Low.

### Option C: Leave as-is

Rely on server always sending valid JSON.

- **Pros:** No code change. **Cons:** Brittle if anything ever alters the attribute. **Effort:** None. **Risk:** Medium over time.

## Recommended Action

Implement Option A (or A+B). Add try/catch around `JSON.parse` and on exception set `data = { balance_series: [], cumulative_pl_series: [] }` so the existing empty-state logic runs.

## Technical Details

- **Affected files:** `app/javascript/controllers/dashboard_charts_controller.js`
- **Components:** Stimulus controller `dashboard-charts`
- **Database changes:** None

## Acceptance Criteria

- [ ] `JSON.parse` is inside a try/catch.
- [ ] On parse error, chart data is treated as empty (both series []).
- [ ] Empty state message is shown when data is invalid (no JS error).
- [ ] Existing tests still pass; optional: add a test that invalid value shows empty state (e.g. data attribute with invalid JSON).

## Work Log

- 2026-03-03: Code review finding created.
- 2026-03-03: Implemented Option A+B: try/catch around JSON.parse with console.warn and fallback to empty balance_series/cumulative_pl_series. Tests pass.

## Resources

- Branch: feat/dashboard-analytics-charts
- Plan: docs/plans/2026-03-03-feat-dashboard-analytics-charts-plan.md
