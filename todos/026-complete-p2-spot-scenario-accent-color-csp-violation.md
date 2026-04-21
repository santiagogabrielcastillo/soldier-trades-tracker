---
status: complete
priority: p2
issue_id: "026"
tags: [code-review, security, frontend, stimulus]
dependencies: []
---

# Fix Pre-existing CSP Violation: `accent-color` Inline Styles in spot_scenario_controller

## Problem Statement

`spot_scenario_controller.js` injects HTML strings containing `style="accent-color:#6366f1"` via `innerHTML` in `_renderCheckboxes` and `_renderSliderRows`. These JS-injected inline style attributes are blocked by the `style-src` CSP directive (which does not include `unsafe-inline`). The budget scenario calculator's checkbox/slider visual styling may be broken in production for users with a strict browser CSP enforcement.

## Findings

- `app/javascript/controllers/spot_scenario_controller.js` — `_renderCheckboxes` (approx. line 208) and `_renderSliderRows` (approx. line 247): JS string templates containing `style="accent-color:#6366f1"`
- These are pre-existing violations not introduced by the chart CSP fix, but surfaced during review of the CSP changes
- `config/initializers/content_security_policy.rb:10` — `style_src :self, :https` — no `unsafe-inline`
- Browser blocks inline `style` attributes in HTML regardless of whether they come from server-rendered HTML or JS `innerHTML`

## Proposed Solutions

### Option 1: Tailwind `accent-indigo-600` class (recommended)

**Approach:** Replace `style="accent-color:#6366f1"` with Tailwind's `accent-indigo-600` utility class in the JS template strings.

```js
// Before
`<input type="checkbox" style="accent-color:#6366f1" ...>`

// After
`<input type="checkbox" class="accent-indigo-600" ...>`
```

Tailwind 3.x ships `accent-{color}` utilities. No custom CSS needed.

**Pros:**
- Fixes the CSP violation
- Uses existing Tailwind conventions
- Simple string replacement

**Cons:**
- Requires confirming `accent-indigo-600` is in the Tailwind safelist or used elsewhere (so it's in the generated stylesheet)

**Effort:** 15 minutes
**Risk:** Low

---

### Option 2: CSS class defined in application stylesheet

**Approach:** Add `.scenario-accent { accent-color: #6366f1; }` to `app/assets/stylesheets/application.css` and reference the class.

**Pros:** Works regardless of Tailwind purge behavior
**Cons:** Adds a custom class when a Tailwind utility already exists

**Effort:** 20 minutes
**Risk:** Low

## Recommended Action

Option 1 — replace `style="accent-color:#6366f1"` with `class="accent-indigo-600"` in both JS template strings. Verify the class is in the built stylesheet (it should be if used elsewhere, or add it to the Tailwind safelist if needed).

## Technical Details

**Affected files:**
- `app/javascript/controllers/spot_scenario_controller.js` — two innerHTML template strings

## Acceptance Criteria

- [ ] No `style="accent-color:..."` in JS-rendered HTML
- [ ] Checkbox/slider accent color is still indigo
- [ ] No new CSP violations in browser console for scenario calculator

## Work Log

### 2026-04-21 - Discovered during code review

**By:** Claude Code (kieran-rails-reviewer agent) — pre-existing violation surfaced during chart CSP fix review
