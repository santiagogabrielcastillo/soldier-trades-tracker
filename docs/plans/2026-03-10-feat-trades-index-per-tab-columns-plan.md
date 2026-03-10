# feat: Trades index per-tab column configuration

---
title: Trades index per-tab column configuration
type: feat
status: completed
date: 2026-03-10
source_brainstorm: docs/brainstorms/2026-03-10-trades-index-per-tab-columns-brainstorm.md
---

## Enhancement Summary

**Deepened on:** 2026-03-10  
**Sections enhanced:** Proposed Solution, Technical Considerations, User Flows / Edge Cases, References & Research.  
**Research sources:** Rails key-value preferences with composite keys, authorization via find-through-association, and existing codebase patterns (`resolve_exchange_account`, `TRADES_INDEX_PARAMS`).

### Key improvements

1. **Authorization:** Resolve exchange account and portfolio **through** `current_user` (e.g. `current_user.exchange_accounts.find_by(id: ...)`) before computing `tab_key`. Use the resolved ID in the key so we never persist a preference for a resource the user doesn’t own; if params refer to a missing/foreign resource, redirect with error and do not save.
2. **Tab key derivation:** Compute `tab_key` only from **validated** context (resolved exchange_account_id / portfolio_id), not raw params, so tampered params cannot create keys for other users’ resources.
3. **Single source of truth:** Reuse the same tab-key logic in both `TradesController` (lookup) and `UserPreferencesController` (save) via a shared helper to avoid drift and duplicate rules.

### New considerations

- **No Pundit/CanCanCan required:** Ownership is enforced by resolving through `current_user` associations; Rails’ `find_by` on the association returns `nil` for wrong/missing IDs, which can be treated as invalid context and redirected.
- **Orphan cleanup:** Optional future enhancement: background job or periodic task to delete preference rows whose key references a non-existent exchange_account_id or portfolio_id; low priority since orphan rows have no functional impact.

---

## Overview

Store a **separate** column visibility configuration for each trades index tab instead of one shared configuration. Tabs are: **History**; each **Exchange** account (e.g. Binance, BingX); and **Portfolio** (with one config when no portfolio is selected and one per selected portfolio). The existing "Columns" modal continues to apply to the **current tab only**; saving updates only that tab’s config and redirects back to the same tab/filters.

## Problem Statement / Motivation

- Today a single `UserPreference` key `trades_index_visible_columns` (array of column IDs) is used for all tabs; the same columns appear on History, every Exchange tab, and every Portfolio view.
- Users want different columns per context (e.g. **Balance** on Portfolio to track running balance in a date range, but hidden on Exchange tabs; or different sets per exchange).

## Proposed Solution

1. **Tab key**  
   Uniquely identify each tab for storage:
   - `history` — History tab
   - `exchange:<exchange_account_id>` — Exchange tab for that account
   - `portfolio` — Portfolio tab when no portfolio is selected
   - `portfolio:<portfolio_id>` — Portfolio tab when a specific portfolio is selected

2. **Storage (composite key)**  
   One `UserPreference` row per tab. Key = `trades_index_visible_columns:#{tab_key}`. Value = JSON array of column IDs (unchanged shape). No schema or value-format change.

3. **Lookup**  
   Resolve `tab_key` from `view` + `exchange_account_id` / `portfolio_id`.  
   - If a row exists for that tab key → use its value (filtered through `TradesIndexColumns.visible_columns`).  
   - Else fall back to legacy key `trades_index_visible_columns` (array) if present.  
   - Else use `TradesIndexColumns::DEFAULT_VISIBLE`.

4. **Save**  
   On PATCH from the column modal: compute `tab_key` from params; `find_or_initialize_by(user_id:, key: "trades_index_visible_columns:#{tab_key}")`; set `value = column_ids`; save; redirect to `trades_path(permitted_params)` so the user stays on the same tab.

5. **UI**  
   No change to modal layout or copy. The modal already sends `view`, `exchange_account_id`, `portfolio_id`; the backend will use them to resolve `tab_key` and read/write the correct preference.

### Research Insights (Proposed Solution)

**Best practices:**
- **Scope for context:** Using a composite key (`trades_index_visible_columns:#{tab_key}`) separates preference contexts without changing the value shape; aligns with “scope for context” patterns in key-value preference stores.
- **JSONB unchanged:** Keeping value as a JSON array of strings avoids migration and keeps one row per tab; no need for a polymorphic or multi-column scope table for this feature.
- **Design for non-queryability:** Preferences remain UI-only and loaded by `user_id` + `key`; no need to query inside the value or add GIN indexes.

**References:**
- Rails Designer – Simple Preferences to Any Resource: scope-based key patterns.
- ActiveRecord::Store and JSONB: existing `user_preferences` value column is already suitable.

## Technical Considerations

- **Tab key helper:** Introduce a small helper (e.g. in `TradesHelper` or a dedicated module) to compute `tab_key` from `view`, `exchange_account_id`, `portfolio_id` so controller and preference logic stay DRY.
- **Controller:** `TradesController#visible_trades_column_ids` must receive current request context (view, exchange_account_id, portfolio_id) and pass it into the preference lookup (or a service/helper that encapsulates key + fallback).
- **UserPreferencesController#update_trades_index_columns:** Accept `view`, `exchange_account_id`, `portfolio_id` from params (already present); compute `tab_key`; validate that the user can access that context (e.g. exchange_account and portfolio belong to current_user); then find_or_initialize by composite key and save. Redirect already uses `TradesHelper::TRADES_INDEX_PARAMS`.
- **Orphan preferences:** If an exchange account or portfolio is deleted, a preference row with key `trades_index_visible_columns:exchange:123` or `...:portfolio:456` may remain. No functional impact; optional future cleanup (e.g. prune keys whose ID no longer exists) can be done later.
- **Validation:** Keep existing rule: at least one column selected; only allow column IDs in `TradesIndexColumns::ALL_IDS`.

### Research Insights (Technical Considerations)

**Authorization (ownership):**
- Resolve resources through the user association so IDs in the key always belong to `current_user`:
  - Exchange: `current_user.exchange_accounts.find_by(id: params[:exchange_account_id])` → use resolved `&.id` in `tab_key`, or treat `nil` as invalid context when `view == "exchange"` and param present.
  - Portfolio: `current_user.portfolios.find_by(id: params[:portfolio_id])` → use resolved `&.id` for `portfolio:<id>`; when view is portfolio but no selection, use literal `"portfolio"`.
- Never use raw `params[:exchange_account_id]` or `params[:portfolio_id]` when building the preference key; use the IDs from the records found through `current_user` so tampered params cannot create keys for other users’ resources.
- No Pundit/CanCanCan needed for this action: find-through-association is sufficient and matches existing `TradesController#resolve_exchange_account` pattern.

**Implementation details (UserPreferencesController):**
```ruby
# 1. Resolve context through current_user (ownership)
exchange_account = params[:exchange_account_id].present? ? current_user.exchange_accounts.find_by(id: params[:exchange_account_id]) : nil
portfolio = params[:portfolio_id].present? ? current_user.portfolios.find_by(id: params[:portfolio_id]) : nil

# 2. Invalid context: view says exchange/portfolio but resolved record missing
if params[:view] == "exchange" && params[:exchange_account_id].present? && exchange_account.nil?
  redirect_back fallback_location: trades_path, alert: "Exchange account not found." and return
end
if params[:view] == "portfolio" && params[:portfolio_id].present? && portfolio.nil?
  redirect_back fallback_location: trades_path, alert: "Portfolio not found." and return
end

# 3. Compute tab_key from validated context (e.g. helper)
tab_key = trades_index_tab_key(params[:view], exchange_account&.id, portfolio&.id)
pref = current_user.user_preferences.find_or_initialize_by(key: "trades_index_visible_columns:#{tab_key}")
pref.value = column_ids
# ... save and redirect
```

**Performance:**
- One extra `find_by(key: ...)` per request (same as today); key is different per tab. No N+1; no querying by value.
- Optional: if the app later loads multiple preferences in one request, consider `current_user.user_preferences.where(key: [...])` and index on `(user_id, key)` (already unique).

**References:**
- Enforcing User Ownership of Resources (Rails demos): use association scope for ownership.
- Rails: `current_user.exchange_accounts.find(params[:id])` raises `RecordNotFound`; `find_by(id: ...)` returns `nil` and is better when param may be absent or invalid.

## User Flows / Edge Cases

- **History:** User on History → Columns → Save → only `trades_index_visible_columns:history` updated; redirect to History with same filters.
- **Exchange A:** User on Exchange A → Columns → Save → only `trades_index_visible_columns:exchange:<A.id>` updated.
- **Portfolio (no selection):** User on Portfolio with no portfolio selected → Columns → Save → only `trades_index_visible_columns:portfolio` updated.
- **Portfolio X:** User on Portfolio with portfolio X selected → Columns → Save → only `trades_index_visible_columns:portfolio:<X.id>` updated.
- **First time on a tab:** No tab-scoped key yet → show DEFAULT_VISIBLE (or legacy key if present); first Save creates the tab-scoped row.
- **Existing user (legacy key only):** Any tab without a tab-scoped key falls back to the existing `trades_index_visible_columns` (array); first Save on that tab creates the tab-scoped key and leaves the legacy row unchanged (other tabs keep using legacy until they are saved).
- **Invalid context:** If someone tampers with `exchange_account_id` or `portfolio_id`, ensure the account/portfolio belongs to `current_user` before saving; otherwise redirect back with error and do not save.

### Research Insights (User Flows / Edge Cases)

**Edge cases:**
- **Tampered params:** Attacker sends `exchange_account_id=999` (another user’s account). Resolve via `current_user.exchange_accounts.find_by(id: 999)` → `nil`; treat as invalid context and redirect with “Exchange account not found.” without saving. Same for `portfolio_id`.
- **Missing param:** User on Exchange tab but param lost (e.g. form bug). If `view == "exchange"` and `exchange_account_id` blank, tab_key can be `"exchange"` (no id) or we could redirect to history; recommend using a key like `exchange:` (empty id) only if we have a convention for “current exchange without id” — otherwise redirect to history to avoid ambiguous state.
- **First save on a tab:** Creates one new row; legacy key remains. Other tabs keep using legacy until they are saved; no need to copy legacy value into every tab key upfront (avoids bulk writes and preserves “lazy” per-tab customization).

**Flow consistency:**
- Ensure redirect after save uses the **same** permitted params (view, exchange_account_id, portfolio_id, from_date, to_date) so the user lands on the same tab with same filters; form already sends these as hidden fields.

## Acceptance Criteria

- [x] **Tab key:** Column preference is stored and read per tab. Tab key = `history` | `exchange:<id>` | `portfolio` | `portfolio:<id>` as above.
- [x] **Lookup:** For the current tab, visible columns are resolved in order: tab-scoped key → legacy key `trades_index_visible_columns` → `DEFAULT_VISIBLE`.
- [x] **Save:** Saving in the Columns modal updates only the current tab’s preference (composite key); redirect preserves view, exchange_account_id, portfolio_id, and date filters.
- [x] **Backward compatibility:** Users with only the legacy key see the same columns on all tabs until they change a tab’s columns; then that tab gets its own row and others continue using the legacy key until they are customized.
- [x] **Authorization:** Save is only allowed when the referenced exchange account or portfolio (if any) belongs to the current user; otherwise redirect with error and do not persist.
- [x] **Validation:** At least one column required; only allowed column IDs; invalid IDs stripped (existing behavior).
- [x] **Tests:** Unit/controller tests for tab key resolution, lookup fallback, save with tab context, and authorization when exchange/portfolio is present.

## Success Metrics

- Users can set different visible columns per tab (History, per exchange, per portfolio).
- Existing users see no change until they customize a tab; then only that tab’s config changes.
- No regression in redirect or filter preservation after saving columns.

## Dependencies & Risks

- **Dependencies:** Existing `UserPreference` model, `TradesIndexColumns`, `TradesHelper::TRADES_INDEX_PARAMS`, and column modal form (already sending view/context params).
- **Risks:** Low. Orphan preference rows after delete are acceptable; optional cleanup later.

## References & Research

### Internal

- Brainstorm: `docs/brainstorms/2026-03-10-trades-index-per-tab-columns-brainstorm.md`
- Predecessor (single config): `docs/plans/2026-03-06-feat-trades-index-columns-configurable-plan.md`
- Trades controller: `app/controllers/trades_controller.rb` (`visible_trades_column_ids`)
- User preferences controller: `app/controllers/user_preferences_controller.rb` (`update_trades_index_columns`)
- Column registry: `app/models/trades_index_columns.rb`
- Trades index view (modal + hidden fields): `app/views/trades/index.html.erb`
- Filter params: `app/helpers/trades_helper.rb` (`TRADES_INDEX_PARAMS`, `trades_index_filter_params`)

### Files to touch (implementation)

- `app/controllers/trades_controller.rb` — pass tab context into column lookup; use tab-scoped key + fallback.
- `app/controllers/user_preferences_controller.rb` — compute tab_key from params; save under composite key; validate exchange/portfolio ownership when present.
- `app/helpers/trades_helper.rb` (or new module) — add `trades_index_tab_key(view, exchange_account_id, portfolio_id)` and optionally centralize "visible column IDs for this tab" logic.
- `test/controllers/user_preferences_controller_test.rb` — add cases for per-tab save and authorization.
- `test/controllers/trades_controller_test.rb` or unit test for tab key / lookup — ensure correct fallback and tab-scoped read.

### External references (deepen-plan)

- Rails key-value preferences and scope-for-context: [Rails Designer – Simple Preferences](https://railsdesigner.com/simple-preferences/).
- Authorization via find-through-association (ownership): [Rails Demos – Enforcing User Ownership](https://human-se.github.io/rails-demos-n-deets-2020/demo-authorization/); use `current_user.exchange_accounts.find_by(id: ...)` so wrong/missing IDs return `nil` and can be handled without Pundit.
