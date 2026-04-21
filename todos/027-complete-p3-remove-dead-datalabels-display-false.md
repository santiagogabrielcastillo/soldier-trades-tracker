---
status: complete
priority: p3
issue_id: "027"
tags: [code-review, quality, frontend]
dependencies: []
---

# Remove Dead `datalabels: { display: false }` Config from Non-Pie Charts

## Problem Statement

`stocks_charts_controller.js` has `datalabels: { display: false }` in the options for `renderTwr`, `renderBar`, and `renderAllocation`. These were added as a defensive measure when `ChartDataLabels` was globally registered. Since the fix moved the plugin to per-chart registration (`plugins: [ChartDataLabels]` on the pie chart only), the plugin never runs on the other three charts. The `datalabels: { display: false }` config is now dead code that misleads future readers into thinking the plugin is still active on those charts.

## Findings

- `app/javascript/controllers/stocks_charts_controller.js:115` — `datalabels: { display: false }` in `renderTwr` options
- `app/javascript/controllers/stocks_charts_controller.js:149` — same in `renderBar`
- `app/javascript/controllers/stocks_charts_controller.js:188` — same in `renderAllocation`
- None of these charts pass `plugins: [ChartDataLabels]`, so Chart.js ignores the datalabels option entirely

## Proposed Solutions

### Option 1: Remove all three dead config entries

```js
// Remove from renderTwr, renderBar, renderAllocation options.plugins blocks:
datalabels: { display: false }  // ← delete this line
```

**Effort:** 5 minutes
**Risk:** None (dead code removal)

## Recommended Action

Delete the three `datalabels: { display: false }` entries.

## Technical Details

**Affected files:**
- `app/javascript/controllers/stocks_charts_controller.js` — lines ~115, ~149, ~188

## Acceptance Criteria

- [ ] No `datalabels` key in `renderTwr`, `renderBar`, or `renderAllocation` options
- [ ] Charts still render correctly
- [ ] No console errors

## Work Log

### 2026-04-21 - Discovered during code review

**By:** Claude Code (kieran-rails-reviewer + code-simplicity-reviewer agents)
