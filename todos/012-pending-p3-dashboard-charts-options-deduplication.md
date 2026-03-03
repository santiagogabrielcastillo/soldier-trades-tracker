# P3: Deduplicate chart options in dashboard_charts_controller

---
status: complete
priority: p3
issue_id: "012"
tags:
  - code-review
  - quality
  - javascript
  - stimulus
---

## Problem Statement

`renderBalanceChart` and `renderPlChart` in `dashboard_charts_controller.js` repeat the same `options` shape (responsive, maintainAspectRatio, scales). Duplication makes it harder to change default behavior (e.g. aspect ratio or height) in one place.

## Findings

- **Location:** `app/javascript/controllers/dashboard_charts_controller.js`, methods `renderBalanceChart` and `renderPlChart`.
- **Repeated:** `responsive: true`, `maintainAspectRatio: false`, `scales.x.type: "category"`. Only difference is `y.beginAtZero` (false vs true) and dataset styling.
- **Impact:** Minor; two small methods, low churn.

## Proposed Solutions

### Option A: Extract defaultOptions() helper

e.g. `defaultChartOptions(yBeginAtZero)` returning shared options; each render method merges dataset-specific config.

- **Pros:** Single place for shared options. **Cons:** Slightly more indirection. **Effort:** Small. **Risk:** Low.

### Option B: Leave as-is

Keep two methods with duplicated options.

- **Pros:** No change, each chart is self-contained. **Cons:** Duplication. **Effort:** None. **Risk:** None.

## Recommended Action

Triage only. Option B is acceptable unless the team adds more charts or often tweaks options.

## Technical Details

- **Affected files:** `app/javascript/controllers/dashboard_charts_controller.js`
- **Database changes:** None

## Acceptance Criteria

- [ ] If refactoring: both charts still render; behavior unchanged.
- [ ] If leaving as-is: no action required.

## Work Log

- 2026-03-03: Code review finding created.
- 2026-03-03: Implemented Option A: added chartOptions(yBeginAtZero) returning shared responsive/maintainAspectRatio/scales config; renderBalanceChart and renderPlChart use this.chartOptions(false) and this.chartOptions(true). Tests pass.

## Resources

- Branch: feat/dashboard-analytics-charts
