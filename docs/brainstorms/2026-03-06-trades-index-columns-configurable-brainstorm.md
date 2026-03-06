# Trades Index: More Columns + Configurable Visibility — Brainstorm

**Date:** 2026-03-06  
**Scope:** Add valuable columns to the trades index (starting with entry point), and make column visibility configurable per user via a modal, with preference stored in a new table.

---

## What We're Building

1. **New columns on the trades table**  
   Add at least **entry price** (entry point) per trade. Optionally add other high-value columns (see below). Columns are rendered only when "visible" in the user's configuration.

2. **Configurable column visibility**  
   A control (e.g. button or icon) in the **top right of the table** opens a **modal** where the user can **select/unselect** which columns to show. The table shows only the selected columns (with a sensible default that includes current columns plus entry).

3. **Saved configuration per user**  
   The chosen set of visible columns is **persisted and unique per user**. When they return (same device/browser or same account, depending on storage), their selection is restored.

4. **Existing behavior**  
   History and Portfolio share **one** column visibility config (same selection in both views).

---

## Columns That Add Value for the Trader

Current columns: Closed, Exchange, Symbol, Side, Leverage, Margin used, ROI, Commission, Net P&amp;L, Balance.

| Column | Description | Data source | Value to trader |
|--------|-------------|-------------|-----------------|
| **Entry price** | Price at which the position was opened | `PositionSummary#entry_price` (already implemented) | Compare to current/exit price; judge quality of entry. |
| **Exit price** | Price at which this leg was closed (closed rows only) | Closing trade’s `avgPrice` / notional from raw (needs exposure on `PositionSummary`) | Compare to entry; see exact exit level. |
| **Open date** | When the position was opened | `PositionSummary#open_at` | Context for holding period and timing. |
| **Quantity** | Size of the position (open qty or closed qty for the row) | `PositionSummary#open_quantity` / `closed_quantity` | Size context next to margin and P&amp;L. |

**Recommendation:** Ship **entry price** first (you called it out). Add **exit price** and **open date** as next optional columns; both are high signal and either already available or easy to derive. Quantity is useful but slightly more optional; can be in the first batch or a follow-up.

---

## Persistence: Three Approaches

| Approach | Description | Pros | Cons |
|----------|-------------|------|------|
| **A: Cookies** | Store visible column IDs (or a compact list) in a cookie, read on page load, write when user saves in the modal. | No DB change; simple; works without login if you ever support anonymous view. | Size limit (~4KB); cleared if user clears cookies; not synced across devices. |
| **B: New table** | e.g. `user_preferences` (user_id, key, value) or `user_table_column_preferences` (user_id, view_context, column_id, visible). | Flexible; survives cookie clear; same config across devices; can extend to other preferences later. | Migration and new model; one more round-trip to load (or cache). |
| **C: JSON column on users** | Add `trades_index_columns` (or `preferences` JSONB) on `users`. Store `{ "visible": ["closed", "exchange", "symbol", "entry_price", ...] }`. | Single table; no new model; sync across devices; fits "one config per user." | Slightly less flexible than a key-value table if you add many unrelated prefs; schema change. |

**Chosen:** **New table (B)** — one shared config for History and Portfolio; extensible for other preferences later.

---

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| New columns (first slice) | Entry price (required); optionally exit price, open date, quantity | Entry adds clear value; others are high signal and mostly already available. |
| UI for configuration | Modal opened from a control in the top right of the table | Keeps table header uncluttered; modal is a familiar pattern for "choose what to show." |
| Default visible columns | Current columns plus entry price (new columns opt-in or default-on by product choice) | Avoids breaking current experience; new columns can be toggled on. |
| Persistence | New table (e.g. `user_preferences`: user_id, key, value) | One config across devices; extensible for other prefs. |
| History vs Portfolio | One shared column config for both views | Simpler; same selection everywhere. |

---

## Resolved Questions

- **Entry point column?** → Yes; show entry price per row.
- **Other valuable columns?** → Exit price, open date, quantity identified as high value; entry + exit + open date recommended for first iteration.
- **Configurable?** → Yes; modal to select/unselect columns; config saved per user.
- **Same config for History and Portfolio?** → One shared config for both views.
- **Persistence?** → New table (e.g. `user_preferences`).

---

## Open Questions

None that block implementation.

---

## Summary

- Add **entry price** (and optionally exit price, open date, quantity) to the trades index.
- Add a **column visibility** control (top right) that opens a **modal** to select/unselect columns; **persist** in a **new table** (e.g. `user_preferences`) per user; **one** config for both History and Portfolio.
- Default: current columns + entry price visible; other new columns can be default-on or opt-in.

Next: run `/plan` to implement.
