# ViewComponent Migration Brainstorm

**Date:** 2026-03-15
**Status:** Ready for planning

---

## What We're Building

A full migration of the UI layer from inline ERB duplication to a **primitive-first ViewComponent hierarchy**. The goal is to eliminate ~10 highly-duplicated UI patterns that are copy-pasted across ~18 view files, establish a consistent design language, and create a foundation for component-level unit testing in a future phase.

---

## Why This Approach

The codebase currently has zero component abstractions — one partial (`portfolios/_form.html.erb`), the rest inline ERB. Research found:

- **Button classes** duplicated verbatim (80+ char strings) in every view file and helpers
- **Stat card** label+value pattern repeated ~20 times across dashboard, spot, stocks pages
- **Tab navigation** copied character-for-character across 3 pages (trades, spot, stocks)
- **Modal dialog** structure copy-pasted between spot and stocks pages
- **Date range filter** form near-identical across trades, spot, and stocks
- **Data table** header/wrapper structure duplicated 3 times
- **Error summary** block duplicated across 3+ forms
- **Empty state** pattern used 5+ times with minor variations

A **primitive-first approach** builds bottom-up so composites always depend on primitives — no circular dependencies, clean hierarchy, and each layer can be tested independently (phase 2).

---

## Key Decisions

### Technology
- **ViewComponent gem** — install fresh, no existing setup to work around
- **Tailwind CSS stays inline** in component templates — no CSS-in-component abstractions
- **No Storybook / component catalogue** — keep tooling overhead low
- **Stimulus wiring preserved** — `data-controller`, `data-action`, `data-*-target` attributes move into component templates exactly as-is

### Component Hierarchy (Three Layers)

#### Layer 1 — Primitives
| Component | Replaces | Key args |
|---|---|---|
| `ButtonComponent` | Inline button class strings everywhere | `variant: :primary/:secondary`, `size:`, `href:` (renders `<a>` or `<button>`) |
| `BadgeComponent` | `<span class="ml-2 rounded bg-slate-100...">` | `label:` |
| `CardComponent` | `<section class="rounded-lg border border-slate-200...">` | `heading:` (optional), content via `yield` |

#### Layer 2 — Composites
| Component | Replaces | Key args |
|---|---|---|
| `StatCardComponent` | 20x repeated label+value pairs | `label:`, `value:`, `signed: false` (auto P&L color) |
| `FormFieldComponent` | Label+input wrapper in all forms | `form:`, `attribute:`, `label:`, `type: :text` |
| `ErrorSummaryComponent` | `bg-amber-50` error list block | `model:` |
| `InlineFieldErrorComponent` | `<p class="mt-1 text-sm text-red-600">` per-field errors | `errors:`, `attribute:` |
| `EmptyStateComponent` | `p-12` centered empty state | `message:`, optional `&block` for CTA |
| `TabNavComponent` | Active/inactive tab nav | `tabs:` array of `{label:, url:, active:}` |

#### Layer 3 — Page-Level
| Component | Replaces | Key args |
|---|---|---|
| `DataTableComponent` | `<div class="overflow-x-auto..."><table>` wrapper | `columns:`, content via slots |
| `DateRangeFilterComponent` | From/To filter form (trades, spot, stocks) | `url:`, `from:`, `to:`, `extra_params:` |
| `ModalComponent` | `data-controller="dialog"` modal wrappers | `title:`, `trigger_label:`, content via `yield` |

### P&L Color Logic
Extract the repeated ternary `value >= 0 ? 'text-emerald-600' : 'text-red-600'` (and nil-guard variant) into a shared helper `pl_color_class(value)` used by `StatCardComponent` and table cell rendering. This replaces the current spread across helpers and inline ERB.

### Helpers That Stay
- `format_money` — stateless, no HTML, no reason to move
- `interval_hint` — single-use in settings
- `trades_index_cell_content` / `trades_index_cell_css` — candidates for a `TradeCellComponent` in phase 2 (currently well-contained in the helper)

### Stimulus Controllers — No Changes
All 6 Stimulus controllers stay exactly as-is. Component templates will include the same `data-controller` / `data-action` / `data-*-target` attributes they currently have. ViewComponent migration is purely server-side.

### Turbo — No Changes
All forms currently opt out of Turbo (`data: { turbo: false }`). This doesn't change with the migration.

---

## Migration Order

Execute in dependency order to avoid forward-referencing:

1. Install ViewComponent gem, configure autoloading
2. Layer 1: ButtonComponent → BadgeComponent → CardComponent
3. Layer 2: StatCardComponent → FormFieldComponent → ErrorSummaryComponent → InlineFieldErrorComponent → EmptyStateComponent → TabNavComponent
4. Layer 3: DataTableComponent → DateRangeFilterComponent → ModalComponent
5. Extract `pl_color_class` helper
6. Update all 18 view files to use components
7. Delete/simplify now-redundant helpers

---

## Effort Estimate

| Phase | Scope | Notes |
|---|---|---|
| Setup | Gemfile + config | ~30 min |
| Layer 1 | 3 primitives | ~2h |
| Layer 2 | 6 composites | ~4h |
| Layer 3 | 3 page-level | ~3h |
| View refactors | 18 files | ~4h |
| **Total** | | **~13–14h focused work** |

---

## Open Questions

*None — all key decisions resolved in dialogue.*

---

## Resolved Questions

| Question | Decision |
|---|---|
| Primary motivation | All three: stop duplication, testability, design consistency |
| Migration scope | Big bang — all views in one pass |
| Stimulus wiring | Preserved exactly as-is inside component templates |
| Component catalogue (Storybook) | Not needed — keep tooling simple |
| Tests | Phase 2 — not part of initial migration |
| Tailwind approach | Utility classes inline inside component `.html.erb` files |

---

## Out of Scope (Phase 2)

- Component unit tests (RSpec + ViewComponent test helpers)
- `TradeCellComponent` (extract `trades_index_cell_*` helpers)
- Turbo Frames / Turbo Streams — separate initiative if desired
- Chart.js Stimulus controller consolidation (`dashboard_charts` + `spot_chart` share logic)
