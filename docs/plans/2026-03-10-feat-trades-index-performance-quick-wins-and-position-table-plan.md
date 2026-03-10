# feat: Trades index performance — quick wins (Phase 1) and Position table (Phase 2, no caching)

---
title: Trades index performance — quick wins and Position table
type: feat
status: completed
date: 2026-03-10
source_brainstorm: docs/brainstorms/2026-03-10-trades-index-attributes-and-platform-performance-brainstorm.md
---

## Enhancement Summary

**Deepened on:** 2026-03-10  
**Sections enhanced:** Proposed Solution (Phase 1 & 2), Technical Considerations, Implementation outline, Dependencies & Risks.  
**Research sources:** Rails view memoization and N+1 prevention, composite index migrations, concerns vs service objects, materialized/derived table sync patterns, project todo 004 (nil exchange_account).

### Key improvements

1. **Memoization:** Prefer computing once per position in the view loop (or a single pre-pass) and passing values into helpers; avoid adding a presenter/decorator unless view logic grows. Eager loading is already in place (`includes(:exchange_account)`); keep it before any future decorator layer.
2. **Shared fetch logic:** Use a **plain module or dedicated service class** (not a controller/model concern) for `leverage_by_symbol` and `current_prices_for_open_positions` — cross-context reuse and easier testing. Preserve nil `exchange_account` handling (filter + log) per `todos/004-pending-p3-index-service-nil-provider-fallback.md` (already implemented).
3. **Composite index:** Use `add_index :trades, [:exchange_account_id, :executed_at]` in a reversible `change` migration; optional explicit `name:` for predictable `remove_index` on rollback.
4. **Phase 2 sync:** Position table is application-maintained (not a DB materialized view). Run position-building after trade sync (e.g. in sync job or `after_commit`); for bulk syncs consider deferring to a background job to avoid long request/transaction time. Backfill once with existing `PositionSummary.from_trades` logic; add tests to keep Position semantics aligned with PositionSummary.

### New considerations

- **DHH-style simplicity:** Prefer in-view memoization or a single pre-loop that builds row hashes over introducing a formal Presenter/Decorator for Phase 1 unless the view becomes hard to follow. Helpers receiving precomputed values are the Rails-friendly approach.
- **Performance:** Phase 1 reduces redundant computation and one query; profile after to confirm next bottleneck (likely still building all positions from 2000 trades until Phase 2).
- **Phase 2 drift risk:** Document that Position rows are derived from Trade; add an optional reconciliation job or health check that compares Position aggregates to PositionSummary.from_trades for a sample to detect drift.

---

## Overview

Improve trades index and platform performance in two phases: **Phase 1** delivers quick wins (memoization, single pref query, shared fetch helpers, optional composite index) with no new caching. **Phase 2** introduces a Position table maintained on sync so the index and dashboard read from the DB instead of building positions from up to 2000 trades on every request. Caching is explicitly out of scope for now; add only if needed after Phase 2.

## Problem Statement / Motivation

- Trades index loads up to 2000 trades, builds all PositionSummaries in Ruby, then paginates to 25 — expensive on every request.
- Per-row computed values (roi, pnl, entry_price, exit_price, quantity, etc.) are recalculated multiple times per position (view + helpers) with no memoization.
- Column visibility triggers two user_preference lookups per request.
- `Trades::IndexService` and `Dashboards::SummaryService` duplicate `fetch_binance_leverage_by_symbol` and `fetch_current_prices_for_open_positions`.
- No composite index on `trades(exchange_account_id, executed_at)` for date-range queries.

## Proposed Solution

### Phase 1 — Quick wins (implement first)

1. **Memoize** per-position values used in the view so each is computed once per position per request: `roi_val`, `pnl_val`, and any helper-used values (e.g. `entry_price`, `exit_price`, `open_quantity`, `closed_quantity`, `open?`, `position_side`, `total_commission`) — either in the view (local variables) or on a presenter/decorator, or by memoizing in a single pass before the table loop.
2. **Single query** for column visibility: load both tab-scoped and legacy preference keys in one `user_preferences.where(key: [key1, key2])` (or equivalent) and resolve in Ruby; update `trades_index_visible_column_ids_for` in `app/helpers/trades_helper.rb`.
3. **Extract shared fetch logic:** Move `fetch_binance_leverage_by_symbol` and `fetch_current_prices_for_open_positions` into a shared module or service (e.g. `app/services/positions/current_data_fetcher.rb` or `app/services/concerns/positions_fetch_current_data.rb`) and use it from both `Trades::IndexService` and `Dashboards::SummaryService`.
4. **Optional:** Add composite index on `trades(exchange_account_id, executed_at)` if profiling shows date-range queries are hot (migration in `db/migrate/`).

### Phase 2 — Position table (long-term, follow-up)

- Add a **Position** (or `position_summaries`) table with one row per position; columns to include: `exchange_account_id`, `symbol`, `position_side`, `leverage`, `open_at`, `close_at`, `margin_used`, `net_pl`, `entry_price`, `exit_price`, `open_quantity`, `closed_quantity`, `total_commission`, and a link to constituent trades (e.g. `trade_ids` array or join table).
- **Sync path:** When trades are synced, run the same grouping/BOTH-chain logic (from `PositionSummary`) once to create/update/close Position rows.
- **Trades index and dashboard:** Query Position with scopes (user/portfolio/date range); paginate with limit/offset on Position; compute balance in SQL (e.g. window over `net_pl`) or store per row.
- **Backfill:** One-time backfill of Position from existing Trade data using current `PositionSummary.from_trades` logic.

### Out of scope (for now)

- **Caching:** No request-level or TTL caching in this pass. Revisit only after Phase 2 if needed.

### Research Insights (Phase 1 & 2)

**View memoization (Phase 1):**
- Compute `roi_val`, `pnl_val`, and any helper-needed fields **once per position** (e.g. in the same loop that renders the row, or in a single pre-pass that builds an array of `{ position:, roi_val:, pnl_val:, ... }`). Pass these into the helper so the helper does not call back into position methods that iterate trades/raw_payload again.
- If you later introduce presenters/decorators, apply eager loading **before** wrapping: e.g. ensure `includes(:exchange_account)` (and any other associations) are loaded at the query level so decorators do not trigger N+1 when accessing associations.
- Memoization inside presenter/decorator methods (e.g. `def roi_val; @roi_val ||= ...; end`) is a valid pattern if you add that layer; for Phase 1, in-view or pre-loop computation is simpler.

**Single preference query:**
- Use `user.user_preferences.where(key: [tab_key, legacy_key])` (or `where(key: [...]).pluck(:key, :value)`), then in Ruby pick the first present value by precedence (tab-scoped over legacy). One query, two keys; avoids two round-trips.

**Shared fetch logic (concern vs service):**
- **Concerns** fit shared behavior across the same type (e.g. multiple models). **Service objects** (or a plain module in `app/services/`) fit logic used across different contexts (IndexService and SummaryService) and allow independent testing without loading controllers or other services.
- Recommendation: extract to a **module or small service class** (e.g. `Positions::CurrentDataFetcher` or `Concerns::PositionsFetchCurrentData` in services). Keep methods class-level: `leverage_by_symbol(trades)`, `current_prices_for_open_positions(positions)`. Both callers pass their already-loaded trades/positions; no new API calls.

**Composite index (Phase 1 optional):**
- Use a reversible migration: `add_index :trades, [:exchange_account_id, :executed_at], name: 'index_trades_on_exchange_account_id_and_executed_at'`. Rails generates the inverse `remove_index` for `change` when using `add_index`. Column order matters for range queries: leading equality (`exchange_account_id`) then range (`executed_at`) is correct for `WHERE exchange_account_id = ? AND executed_at BETWEEN ? AND ?`.

**Phase 2 — keeping Position in sync:**
- Position is application-maintained (normal table), not a PostgreSQL materialized view. After each trade sync (or in a post-sync job), run the same grouping/BOTH-chain logic and upsert Position rows. For **bulk** syncs (e.g. initial import or large backfill), prefer a **background job** to recompute positions so the request or transaction does not hold locks too long.
- If you ever use DB materialized views elsewhere: they do not auto-update; refresh (e.g. `REFRESH MATERIALIZED VIEW`) must be triggered explicitly (callback, job, or trigger). For Position we are writing rows from application code, so no materialized view refresh pattern is required.

**Edge cases:**
- **Nil exchange_account:** Already handled per `todos/004-pending-p3-index-service-nil-provider-fallback.md`: filter to `positions.select { |p| p.exchange_account.present? }` before grouping; log when skipping. Preserve this behavior in the shared fetcher.
- **Phase 2 drift:** If a sync job fails partway or logic diverges, Position rows can drift from Trade data. Mitigate with: tests that compare PositionSummary.from_trades(trades) output to Position rows for the same trade set; optional periodic reconciliation job or health check.

**References:**
- [Rails View Patterns: Helpers vs Partials vs Presenters vs Decorators](https://blog.railsforgedev.com/rails-view-patterns-helpers-vs-partials-vs-presenters-vs-decorators)
- [Rails N+1 and decorators](https://dev.to/agustincchato/rails-n-1-query-and-decorators-16mb) — eager load before decorate
- [Understanding Compound Indexes in PostgreSQL and Ruby on Rails](https://patrickkarsh.medium.com/understanding-compound-indexes-in-postgresql-and-ruby-on-rails-d39bf165303b)
- [When to Use Concerns vs Service Objects in Rails](https://www.derekneighbors.com/2025/01/13/concerns-vs-service-objects)

## Technical Considerations

- **Memoization:** Prefer computing `roi_val` and `pnl_val` once per position in the view (or in a single loop that builds a small struct/hash per row) so the helper receives them and does not trigger recomputation. Avoid adding state to `PositionSummary` unless we introduce a view-specific decorator.
- **Shared fetchers:** Preserve existing behavior (group by provider, call Binance/Bingx ticker fetchers, merge by symbol; Binance leverage from client). Handle nil `exchange_account` as today (e.g. log and skip or fallback per existing todo).
- **Index:** Composite index is additive and low-risk; make migration reversible.
- **Phase 2:** Position table design should align with current `PositionSummary` semantics (BOTH chains, partial closes, over-close) so sync logic can be extracted from `PositionSummary` and run in a job or sync pipeline.

**Performance (algorithmic):**
- Phase 1 does not change the dominant cost: building all positions from up to 2000 trades. It removes redundant per-row work (memoization) and one query (prefs). After Phase 1, if the index is still slow, profile to confirm position-building is the bottleneck before investing in Phase 2.
- Phase 2 reduces time complexity for the index from O(trades) build + O(1) paginated read to O(page_size) read from Position with appropriate indexes (e.g. on `exchange_account_id`, `close_at`/`open_at` for ordering).

## Acceptance Criteria

### Phase 1

- [x] Trades index view (and helpers) compute `roi_val`, `pnl_val`, and any other per-position values once per position per request (no repeated calls to `unrealized_roi_percent`, `unrealized_pnl`, `roi_percent`, `entry_price`, `exit_price`, `open_quantity`, `closed_quantity`, `total_commission`, `position_side` for the same position).
- [x] Column visibility uses a single user_preferences query (tab-scoped + legacy keys) in `trades_index_visible_column_ids_for`.
- [x] `fetch_binance_leverage_by_symbol` and `fetch_current_prices_for_open_positions` live in a shared module or service; both `Trades::IndexService` and `Dashboards::SummaryService` use it. No new external API calls; behavior unchanged.
- [x] (Optional) Migration adds composite index `trades(exchange_account_id, executed_at)` and is reversible.
- [x] Existing tests pass; trades index and dashboard still render correctly (manual or automated).

### Phase 2 (follow-up)

- [x] Position table exists with required columns and associations; sync (or post-sync job) creates/updates/closes Position rows from Trade data.
- [x] Trades index and dashboard read from Position with appropriate scopes and pagination (with fallback to PositionSummary when no Position rows).
- [x] Backfill script or task populates Position from existing trades; no regression in displayed data.

## Success Metrics

- Phase 1: Fewer redundant computations per request; one fewer query for column prefs; single place for fetch logic; optionally faster date-range trade queries.
- Phase 2: Trades index and dashboard avoid loading 2000 trades and building all positions on each request; pagination is DB-level.

## Dependencies & Risks

- **Phase 1:** Low risk. Shared fetcher must preserve nil/error handling (see `todos/004-pending-p3-index-service-nil-provider-fallback.md`).
- **Phase 2:** Sync path must stay in sync with PositionSummary semantics; failed jobs or bugs could cause Position/Trade drift. Mitigate with tests and optional reconciliation job.

## References & Research

- **Brainstorm:** `docs/brainstorms/2026-03-10-trades-index-attributes-and-platform-performance-brainstorm.md`
- **Index service:** `app/services/trades/index_service.rb` (lines 80–117: fetch_binance_leverage_by_symbol, fetch_current_prices_for_open_positions)
- **Dashboard service:** `app/services/dashboards/summary_service.rb` (lines 111–147: same methods)
- **View:** `app/views/trades/index.html.erb` (lines 86–88: roi_val, pnl_val per row)
- **Helper:** `app/helpers/trades_helper.rb` (trades_index_visible_column_ids_for, trades_index_cell_content)
- **PositionSummary:** `app/models/position_summary.rb` (from_trades, build_summaries, BOTH chains, roi_percent, unrealized_*)

## Implementation outline (Phase 1)

| Task | File(s) | Notes |
|------|---------|--------|
| Memoize per-position values for view | `app/views/trades/index.html.erb`, optionally `app/helpers/trades_helper.rb` | Compute roi_val, pnl_val (and any helper-needed fields) once per position; pass into helper. |
| Single query for column visibility | `app/helpers/trades_helper.rb` | `user_preferences.where(key: [tab_key_pref, legacy_key]).` then pick first present value. |
| Extract shared fetch logic | New: e.g. `app/services/positions/current_data_fetcher.rb` or `app/services/concerns/positions_fetch_current_data.rb`; `app/services/trades/index_service.rb`; `app/services/dashboards/summary_service.rb` | Module or class with `leverage_by_symbol(trades)` and `current_prices_for_open_positions(positions)`; both services call it. |
| Optional composite index | New migration in `db/migrate/` | `add_index :trades, [:exchange_account_id, :executed_at]` (reversible). |

**Phase 1 implementation details:**

- **Preference keys for single query:** Tab-scoped key is `"trades_index_visible_columns:#{tab_key}"` (from `trades_index_tab_key`); legacy key is `"trades_index_visible_columns"`. Query: `user.user_preferences.where(key: [tab_scoped_key, legacy_key])`; then resolve: use tab-scoped value if present, else legacy, else `TradesIndexColumns::DEFAULT_VISIBLE`.
- **Shared fetcher interface:** Either a module with module methods or a class with class methods, e.g. `Positions::CurrentDataFetcher.leverage_by_symbol(trades)` and `Positions::CurrentDataFetcher.current_prices_for_open_positions(positions)`. Both IndexService and SummaryService call these; no change to external API (Binance/Bingx) or to grouping/merge behavior. Preserve filtering of positions with `exchange_account.present?` and logging when skipping nil (see todo 004).

## Implementation outline (Phase 2 — high level)

| Task | Notes |
|------|--------|
| Design Position schema | Columns, indexes, association to Trade (has_many trades or trade_ids). |
| Migration + model | Create positions table; Position model with scopes (e.g. by user, portfolio date range). |
| Sync integration | After trade sync, run position-building logic; create/update/close Position records. |
| Backfill | One-time job: load trades per user/account, run PositionSummary-style grouping, insert Position rows. |
| Switch index + dashboard | TradesController and Dashboards::SummaryService read from Position; remove or reduce reliance on building from 2000 trades. |
