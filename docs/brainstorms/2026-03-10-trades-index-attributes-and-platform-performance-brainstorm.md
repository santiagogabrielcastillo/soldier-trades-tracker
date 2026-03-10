# Trades Index Attributes Audit & Platform Performance — Brainstorm

**Date:** 2026-03-10  
**Scope:** (1) Review which attributes on the trades index are stored in the DB vs calculated on the fly; (2) Review and improve performance across the platform (N+1, caching, etc.).

---

## What We're Building

1. **Clear audit** of trades index columns: source of truth (DB vs in-memory vs computed per request).
2. **Targeted performance improvements** for the trades index and shared code paths (dashboard, preferences).
3. **No scope creep:** Fix real bottlenecks first; avoid preemptive caching or schema changes that aren’t justified.

---

## Trades Index: Where Data Lives

**Important:** There is **no Position table**. Rows on the trades index are **PositionSummary** objects built in Ruby from **Trade** records.

- **DB:** `Trade` (exchange_account_id, symbol, side, fee, net_amount, executed_at, raw_payload, position_id, …).  
- **In memory:** Up to **2000** trades are loaded per request, then `PositionSummary.from_trades_with_balance(trades, …)` builds a list of positions. Pagination (25 per page) is applied **after** building the full list.
- **External:** `current_prices` (ticker API per provider for open positions); Binance `leverage_by_symbol` (API per Binance account).

### Column-by-Column Audit

| Column       | Stored in DB? | Where it comes from |
|-------------|----------------|----------------------|
| **closed**  | No             | `open? ? "Open" : close_at` — `close_at` set on PositionSummary in build. |
| **exchange**| Indirect       | `pos.exchange_account.provider_type` — account from first trade (loaded via `includes(:exchange_account)`). |
| **symbol**  | Yes (Trade)    | PositionSummary.symbol (from first trade). |
| **side**    | Indirect       | `position_side` — computed from first trade’s `raw_payload` (positionSide/side). |
| **leverage**| Indirect       | PositionSummary.leverage — from trade raw or Binance API. |
| **margin_used** | No         | Computed in build (notional/leverage) or `remaining_margin_used`. |
| **roi**     | No             | **In view:** `open? ? unrealized_roi_percent(current_prices[symbol]) : roi_percent` — both are methods on PositionSummary over its trades. |
| **commission** | Yes (Trade.fee) | `total_commission` — sums fees from position’s trades (opening/closing legs). |
| **net_pl**  | Partially      | Set on PositionSummary in build; **view** uses it for closed, or `unrealized_pnl(current_prices[symbol])` for open. |
| **balance** | No             | Assigned in `assign_balance!` (running balance from cumulative net_pl). |
| **entry_price** | No        | Computed from position’s opening trades / raw (VWAP when multiple opens). |
| **exit_price**  | No        | Computed from closing trade(s) raw (avgPrice, quoteQty/qty). |
| **open_date**   | Yes (Trade.executed_at) | PositionSummary.open_at (first trade’s executed_at). |
| **quantity**    | No        | `open? ? open_quantity : closed_quantity` — both derived from trades’ raw_payload (executedQty, etc.). |

**Summary:** Only **symbol**, **fee** (commission), and **executed_at** (open_date) are first-class DB columns on Trade. Everything else is either set on the in-memory PositionSummary during build or **computed on demand** from the position’s `trades` array and `raw_payload`.

---

## Performance Issues Identified

### 1. Load-then-paginate (high impact)

- **Current:** Load up to **2000** trades → build **all** PositionSummaries → then paginate to 25.
- **Effect:** Full grouping, BOTH-chain splitting, balance assignment, and (for open positions) current price fetch happen for the entire set on every request, even though we only render one page.

### 2. Per-row computation in the view (medium impact)

- For each of 25 rows we call `pos.open?`, then `unrealized_roi_percent` / `unrealized_pnl` (open) or `roi_percent` / `net_pl` (closed).
- Those methods (and others like `entry_price`, `exit_price`, `open_quantity`, `closed_quantity`, `total_commission`, `position_side`) iterate over the position’s trades and `raw_payload` with no memoization. Same work can be repeated for the same position (e.g. in helpers for content and CSS).

### 3. No caching (low–medium, depending on traffic)

- No fragment or request-level caching. `current_prices` are fetched every request (needed for open PnL); built positions are not cached.
- Development uses `null_store`; production has cache_store commented (memory/mem_cache).

### 4. Duplicate logic across services (maintainability + minor perf)

- `Trades::IndexService` and `Dashboards::SummaryService` each implement `fetch_binance_leverage_by_symbol` and `fetch_current_prices_for_open_positions` with the same logic. Duplication and extra API calls when both dashboard and trades index are used in a session.

### 5. User preferences (low impact)

- `trades_index_visible_column_ids_for` does **two** `user_preferences.find_by(key: …)` (tab-scoped key, then legacy key). Could be a single query (e.g. `where(key: [key1, key2]).find_by(...)` or load both in one go).

### 6. Trades table indexes (possible gain)

- Queries filter by `exchange_account_id` and `executed_at` (e.g. portfolio date range, history filters). There is an index on `exchange_account_id` but no composite `(exchange_account_id, executed_at)`. A composite index could help for date-range-heavy workloads.

### 7. Binance leverage API (external)

- One external call per Binance account on every trades index (and dashboard) load. Acceptable if accounts are few; could be cached short-term if needed.

---

## Approaches

### A: Quick wins only (minimal change)

- **Memoize** per-position computed values used in the view (e.g. roi_val, pnl_val, entry_price, exit_price, open_quantity, closed_quantity) so each is computed once per position per request.
- **Single query** for column visibility: load tab-scoped + legacy pref in one call and resolve in Ruby.
- **Extract** shared `fetch_binance_leverage_by_symbol` and `fetch_current_prices_for_open_positions` into a small module or service used by both IndexService and SummaryService (no new API calls, less duplication).
- **Optional:** Add composite index on `trades(exchange_account_id, executed_at)` if profiling shows heavy date-range queries.

**Pros:** Low risk, small diff, immediate benefit from memoization and one less pref query.  
**Cons:** Does not address “load 2000 trades / build all positions then show 25”; that remains the main cost.

### B: Paginate before building positions (structural)

- Change flow so we **paginate at the trade level** (or at “position identifier” level) before building full PositionSummaries. For example: compute a stable “position key” per row, sort by (open first, then close_at desc), apply limit/offset, then load only the trades needed for those positions and build PositionSummaries for the current page.
- Requires defining how “position key” is determined from DB (e.g. symbol + position_id + chain) and possibly persisting or computing it without loading 2000 trades. May require a DB-backed “position” or “position_key” to make pagination efficient.

**Pros:** Addresses the main bottleneck (over-fetch and over-build).  
**Cons:** Non-trivial design (position boundaries and sorting are currently defined in Ruby over full trade set); risk of bugs and edge cases (BOTH chains, partial closes).

### C: Cache built positions and/or current prices (targeted caching)

- Cache the **built position list** (or the trade set + built list) per user/view/filter key with a short TTL (e.g. 30–60 s) so repeat requests or dashboard + index in same session don’t rebuild.
- Optionally cache **current_prices** per provider/symbols with a very short TTL (e.g. 10–30 s) to avoid hitting the ticker API on every request.
- Keep cache keys narrow (user, view, portfolio_id, exchange_account_id, date range, page).

**Pros:** Can significantly cut CPU and external calls for repeated or concurrent loads.  
**Cons:** Cache invalidation on new trades (sync) must be considered; more moving parts; only helps when same data is requested again.

### D: Position table (persist positions in the DB)

- Introduce a **Position** (or `position_summaries`) table: one row per position (same logical entity as today’s PositionSummary), with stored columns such as: `exchange_account_id`, `symbol`, `position_side`, `leverage`, `open_at`, `close_at`, `margin_used`, `net_pl`, `entry_price`, `exit_price`, `open_quantity`, `closed_quantity`, `total_commission`, and a link to the trades that make up the position (e.g. `trade_ids` array or join table).
- **Population:** Run the same grouping/BOTH-chain logic **once** when trades are synced (or in a background job after sync): create/update/close Position rows from the incoming Trade set. Alternatively, a materialized view or periodic job could rebuild positions from trades.
- **Trades index:** Query Position with scopes (portfolio date range, exchange, user via exchange_account). **Pagination is trivial** (limit/offset on positions). Balance can be computed in SQL (window function over `net_pl`) or stored/cached per position.
- **Dashboard:** Can aggregate from Position instead of rebuilding from 2000 trades.

**Pros:** Fixes load-then-paginate at the source; index and dashboard read simple rows; many columns are stored (no per-request derivation); one place for position boundaries (BOTH chains, partial closes) — logic runs on sync, not every request.  
**Cons:** New schema and migrations; must keep positions in sync with trades (sync pipeline or job must create/update/close positions; bugs or failed jobs can cause drift); same edge-case logic (BOTH, partial closes, over-close) lives in the sync path and must stay aligned with current PositionSummary behavior. Initial rollout may require a backfill from existing trades.

**When it’s best suited:** You’re willing to own a Position model and sync story long-term; you want the index and dashboard to scale without re-running position-building on every request.

---

## Recommendation

- **Phase 1 — Approach A (quick wins):** Memoization in the view layer, single pref query, shared fetch helpers, and optional composite index. Delivers measurable improvement with minimal risk.
- **Phase 2 — Approach D (Position table), long-term:** Introduce a Position table; maintain it when trades sync; backfill from existing trades; switch trades index and dashboard to read from Position. Pagination and display then use DB-backed positions (natural pagination, stored columns).
- **Caching (C):** Add only if needed after D (e.g. short-TTL for current_prices); invalidation on sync.

---

## Key Decisions

- **Attribute audit:** Documented above; no new DB columns for “position” attributes in this pass — we only improve how we compute and use existing data.
- **Long-term solution: Position table (Approach D).** We will introduce a Position table, maintained on sync, and have the trades index and dashboard read from it. Quick wins (A) first; then implement D (schema, sync pipeline, backfill, switch reads to Position).
- **Performance priority:** First reduce redundant work (A); then implement Position table (D) for natural pagination and stored columns. Caching (C) only if needed after D.
- **Shared code:** Extract Binance leverage and current-prices fetching into a shared module/service used by both Trades::IndexService and Dashboards::SummaryService.

---

## Open Questions

*(None.)*

---

## Resolved Questions

- **Long-term approach:** Approach D (Position table) — persist positions in the DB, maintained on sync; trades index and dashboard will read from Position. Paginate and display from the Position table; no “load 2000 trades then build all positions” on each request.
- **Caching:** No caching for now. Keep the first iteration cache-free; add caching only if needed after Phase 2 (Position table).
