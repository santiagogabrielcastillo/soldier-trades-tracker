# Trades Index: Per-Tab Column Configuration — Brainstorm

**Date:** 2026-03-10  
**Scope:** Allow a separate column visibility configuration for each trades index tab (History, each Exchange account, each Portfolio) instead of one shared configuration for all tabs.

---

## What We're Building

- **Per-tab column config:** Each “tab” on the trades index has its own saved set of visible columns.
- **Tab definition (Option C — fully per-tab):**
  - **History** → one config (key: history).
  - **Exchange** → one config **per exchange account** (e.g. key: exchange:123).
  - **Portfolio** → one config **per portfolio** (e.g. key: portfolio:456).
- **Examples:** User can show Balance on Portfolio (to track running balance in a date range) and hide it on Exchange tabs; or show different columns on Binance vs BingX.
- **Default for new tabs:** When a tab has no saved config yet, use `TradesIndexColumns::DEFAULT_VISIBLE` (no inheritance from another tab).
- **UI:** The existing “Columns” modal applies to the **current tab only**. Saving updates only that tab’s config and redirects back to the same tab.

---

## Why This Approach

- **User need:** Different contexts (history vs a specific exchange vs a specific portfolio) benefit from different columns (e.g. Balance on portfolio, not on exchange).
- **Existing behavior:** One `UserPreference` key `trades_index_visible_columns` (array of column IDs); same columns on every tab. Form already sends `view`, `exchange_account_id`, `portfolio_id` for redirect but the controller ignores them when saving.
- **Choice C (fully per-tab)** gives maximum flexibility with a simple rule: one config per tab as shown in the UI.

---

## Approaches

| Approach | Description | Pros | Cons |
|----------|-------------|------|------|
| **A: Composite key per tab** | One `UserPreference` row per tab. Key = `trades_index_visible_columns:#{tab_key}` where `tab_key` is `history`, `exchange:<id>`, or `portfolio:<id>`. Value = array of column IDs (same as today). Lookup: `find_by(key: ...)`; fallback: `DEFAULT_VISIBLE`. | No schema change; simple read/write; one row per tab; backward compat by falling back to legacy key when no tab key exists. | More rows per user (1 + # exchanges + # portfolios). |
| **B: Single key, value = hash** | Keep one key `trades_index_visible_columns`; value = JSON object `{ "history" => [...], "exchange:123" => [...], "portfolio:456" => [...] }`. Read: parse and use `hash[tab_key] || DEFAULT_VISIBLE`. Save: read hash, merge in current tab, write back. | Single row; all configs in one place. | Read-modify-write on every save; need to migrate existing array value to hash (e.g. treat as `"history"` or apply to all keys once). |

**Recommendation:** **A (composite key).** Simpler (no JSON merge, no migration of value shape). `UserPreference` already supports many keys per user; the number of rows is bounded and small. Backward compatibility: if the current tab has no tab-scoped key, fall back to the legacy key `trades_index_visible_columns` (array) if present, else `DEFAULT_VISIBLE`; so existing users keep their current columns until they change a tab.

---

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Granularity | One config per tab (History, per exchange, per portfolio) | User chose Option C for maximum flexibility. |
| Tab key format | `history`, `exchange:<exchange_account_id>`, `portfolio:<portfolio_id>` | Uniquely identifies each tab; stable and URL-aligned. |
| Storage | Composite preference key per tab (Approach A) | Simple; no value migration; backward compat via fallback. |
| Default for new tab | `TradesIndexColumns::DEFAULT_VISIBLE` | Predictable; no surprising inheritance from another tab. |
| Legacy key | Keep `trades_index_visible_columns` (array) as fallback when no tab key exists | Existing users see no change until they save per-tab; then we write tab-scoped key. |

---

## Resolved Questions

- **Scope of “tab”?** → Fully per-tab: History, each Exchange account, each Portfolio (Option C).
- **Default for a tab with no saved config?** → Use `DEFAULT_VISIBLE` (no cross-tab inheritance).
- **Storage approach?** → Composite key per tab (multiple `UserPreference` rows).

---

## Open Questions

None that block implementation.

---

## Summary

- **Goal:** Separate column visibility per trades index tab (History, per exchange, per portfolio).
- **Mechanism:** Store one `UserPreference` per tab with key `trades_index_visible_columns:#{tab_key}` and value = array of column IDs. Controller and view resolve `tab_key` from `view` + `exchange_account_id` / `portfolio_id`; lookup with fallback to legacy key then `DEFAULT_VISIBLE`.
- **UI:** No change to modal layout; “Columns” still applies to current tab; save updates only that tab’s config and redirects back with same tab/filters.

Next: run `/plan` to implement.
