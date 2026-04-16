# Spot Scenario Calculator — Design Spec

**Date:** 2026-04-16
**Status:** Approved

---

## Overview

A scenario calculator embedded in the Spot portfolio page. It lets the user play with cash allocations across open spot positions and instantly see projected ROI — either manually via sliders or automatically via an optimizer. Ephemeral: no persistence, resets on close.

---

## User Mental Model

The user thinks in terms of portfolio allocation percentages:
> "I'm at 75% cash. I want to drop to 65% and use that freed capital to move my deepest positions up toward −30% drawdown."

The calculator translates that mental model into concrete dollar amounts per position, showing projected breakeven and ROI in real time.

---

## Placement

An inline collapsible panel below the positions table on the existing Spot Portfolio tab. A header bar (indigo accent) with "▼ Scenario calculator" toggles expand/collapse. The panel is closed by default.

No new routes or pages. No persistence ("ephemeral · resets on close" badge visible in the header).

---

## Cash Budget Section

Two linked inputs, always visible at the top of the open panel:

| Input | Description |
|---|---|
| **Target cash %** | Number field. User types the desired cash % after investing. |
| **Budget to invest ($)** | Dollar amount derived from target %. Editing either updates the other. |

Formula:
```
budget = current_cash_balance − (target_cash_pct / 100) × total_portfolio_value
```

A summary line shows: "After invest: cash = $X (Y%)" — confirming the post-investment state.

The server provides `current_cash_balance`, `spot_value`, and `total_portfolio_value` as JSON data attributes on the panel element. All arithmetic runs client-side in the Stimulus controller.

---

## Two Modes: Manual and Optimize

A two-segment tab switcher below the budget section. Switching tabs preserves the budget inputs.

---

### Manual Mode

A table of all open positions with one row per token. For each row:

| Column | Description |
|---|---|
| Token | Token name |
| Breakeven | Current net breakeven price |
| Current ROI | `(current_price − breakeven) / breakeven × 100` |
| Inject slider | Range input, 0 → total budget. Dragging redistributes remaining budget. |
| Inject $ | Dollar amount for this position (derived from slider position) |
| New ROI | Recalculated ROI after hypothetical injection (see math below) |

**Slider constraint:** The sum of all injections cannot exceed the budget. When a slider is dragged, the remaining budget decreases. If the user pushes one slider to a value that would exceed the budget, it clamps at the remaining available amount.

**Budget progress bar** below the table: filled bar showing allocated vs total budget, with "$ remaining" text.

**Live recalculation** — every `input` event on any slider triggers:
```
new_balance   = current_balance + injection / current_price
new_net_usd   = net_usd_invested + injection
new_breakeven = new_net_usd / new_balance
new_roi       = (current_price − new_breakeven) / new_breakeven × 100
```

---

### Optimize Mode

**Configuration row:**

1. **Optimizer mode toggle** — two-segment: "Fixed target ROI" / "Best achievable floor"
2. **Target ROI input** (shown only in Fixed target mode) — number field, default −30%
3. **Position checkboxes** — one per open position; user selects which to include
4. **Optimize button** — runs the algorithm and renders results

**Optimizer algorithms:**

*Fixed target ROI mode:*

For each selected position, compute the exact injection needed to reach the target ROI:
```
target_breakeven = current_price / (1 + target_roi / 100)

# Cash needed to move breakeven to target_breakeven:
# (net_usd + a) / (balance + a / current_price) = target_breakeven
# Solving for a:
a = (target_breakeven × balance − net_usd) / (1 − target_breakeven / current_price)
```
If a position already meets or exceeds the target, it gets $0. Allocations are capped at the remaining budget — positions are processed in order of "most cash needed" first, so the deepest positions are prioritized. Any budget that can't cover a position fully is applied partially.

*Best achievable floor mode:*

Binary search for the highest ROI floor `r*` such that the total cash needed to bring all selected positions to `r*` is ≤ the available budget (converges when within $1). Each step computes the required injection per position as above. The result is the equal ROI all selected positions can be brought to simultaneously, using as much of the budget as possible.

**Results table** — same columns as manual mode plus a **Status badge**:
- `Target met` (amber) — position reached exactly the target ROI
- `Already past target` (green) — position was already better than target, $0 injected
- `Budget exhausted` (orange) — position received partial injection, budget ran out
- In Best floor mode, all selected positions show `Equalized` (indigo); unselected positions appear greyed out with $0 injection and no badge

**Summary line** below the results: "Total injected: $X · N of M positions reached target"

---

## Architecture

**Approach:** Pure Stimulus controller. No new server routes.

### Data flow

1. Rails renders the panel element with position data as a JSON `data-` attribute:
   ```html
   <div data-controller="spot-scenario"
        data-spot-scenario-positions-value='[{"token":"BTC","balance":"0.5","net_usd_invested":"36200","breakeven":"72400","current_price":"42100"}, ...]'
        data-spot-scenario-cash-balance-value="12400"
        data-spot-scenario-spot-value-value="4120"
        data-spot-scenario-total-portfolio-value="16520">
   ```
2. The Stimulus controller (`spot_scenario_controller.js`) reads these values on connect and drives all UI state.
3. No server round-trips after mount. All arithmetic is JavaScript.

### Stimulus controller responsibilities

- Toggle panel open/close
- Sync target cash % ↔ budget dollar inputs
- Render slider rows for manual mode; handle drag constraints (sum ≤ budget)
- Run both optimizer algorithms on button click
- Render results table with status badges
- Switch between Manual/Optimize tabs

### Files to create/modify

| File | Change |
|---|---|
| `app/javascript/controllers/spot_scenario_controller.js` | New Stimulus controller (all calculator logic) |
| `app/views/spot/index.html.erb` | Add collapsible panel partial below positions table |
| `app/views/spot/_scenario_calculator.html.erb` | New partial — panel HTML with data attributes |
| `app/controllers/spot_controller.rb` | Pass `@total_portfolio`, `@spot_value`, `@cash_balance`, and serialized positions JSON to the view (most already computed in `load_index_data`) |

---

## UI / UX Notes

> **Implementation note:** Use the `frontend-design` skill when building the panel UI to ensure production-grade visual quality. The panel uses an indigo accent palette (`#6366f1` family) to visually distinguish it from the slate-toned positions table above.

Key UI details:
- Panel header: indigo left border, subtle purple-tinted background
- Sliders: `accent-color: #6366f1`
- New ROI column: color-coded — red (worse than current), amber (improved but still negative), green (positive)
- Status badges: pill shape, color-coded (see above)
- Budget progress bar: indigo fill, depletes as allocations are made
- Tab switcher: same segment style as the existing TabNavComponent but inline

---

## Edge Cases

| Case | Behavior |
|---|---|
| Position already at or better than target ROI | Optimizer skips it ($0 injection), badge: "Already past target" |
| Budget insufficient to reach target for any position | Inject whatever is available; show "Budget exhausted" badge |
| Budget = $0 (already at target cash %) | Sliders all locked at 0; Optimize button disabled with tooltip |
| current_price missing (not synced) | Row shown greyed out, slider disabled, tooltip: "Sync prices first" |
| Risk-free position (net_usd_invested < 0) | Breakeven shown as $0; ROI shown as ∞ or "Risk free"; excluded from optimizer |

---

## Out of Scope

- Saving/naming scenarios
- Executing the scenario (creating actual buy transactions from it)
- Multi-account support (always operates on the default spot account)
- Historical simulation (what if I had done this 30 days ago)
