# P3: Reduce dashboard controller instance variable boilerplate

---
status: complete
priority: p3
issue_id: "011"
tags:
  - code-review
  - quality
  - rails
  - refactor
---

## Problem Statement

`DashboardsController#show` assigns 14+ instance variables from the `Dashboards::SummaryService` result hash. Adding new analytics keys requires editing both the service and a new controller line. This is repetitive and can be simplified.

## Findings

- **Location:** `app/controllers/dashboards_controller.rb`
- **Current pattern:** One `@var = result[:key]` per key. Works but verbose.
- **Impact:** Maintainability only; no functional or performance issue.

## Proposed Solutions

### Option A: Pass result hash as a single instance variable (e.g. @dashboard)

View uses `@dashboard[:summary_balance]`, etc. (or a Struct/OpenStruct for dot access).

- **Pros:** One assignment; new keys require no controller change. **Cons:** View must use hash/struct. **Effort:** Small. **Risk:** Low.

### Option B: Delegate to a presenter object

e.g. `@dashboard = Dashboards::ShowPresenter.new(result)` with method_missing or explicit methods for each key.

- **Pros:** Clean view API, testable presenter. **Cons:** Extra class, might be YAGNI. **Effort:** Medium. **Risk:** Low.

### Option C: Leave as-is

Keep explicit instance variables for clarity and grep-friendliness.

- **Pros:** No change, very explicit. **Cons:** Boilerplate. **Effort:** None. **Risk:** None.

## Recommended Action

Triage only. Option C is acceptable; consider A if the team adds many more dashboard keys later.

## Technical Details

- **Affected files:** `app/controllers/dashboards_controller.rb`, optionally `app/views/dashboards/show.html.erb`
- **Database changes:** None

## Acceptance Criteria

- [ ] If refactoring: view still renders correctly; controller tests pass.
- [ ] If leaving as-is: no action required.

## Work Log

- 2026-03-03: Code review finding created.
- 2026-03-03: Implemented Option A: controller assigns result to single @dashboard = OpenStruct.new(result) with summary_trades_path set from result; view updated to use @dashboard.* throughout. Tests pass.

## Resources

- Branch: feat/dashboard-analytics-charts
