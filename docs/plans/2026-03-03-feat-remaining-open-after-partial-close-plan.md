# feat: Show "remaining open" row after partial close

---
title: Show remaining open row after partial close
type: feat
status: completed
date: 2026-03-03
source_todo: todos/012-pending-p2-remaining-open-after-partial-close.md
---

## Enhancement Summary

**Deepened on:** 2026-03-03  
**Sections enhanced:** Technical Considerations, Implementation outline, Dependencies & Risks  
**Research sources:** PositionSummary implementation (attr_reader, open_quantity, margin_used, total_commission, assign_balance!, sort), open-trades plan.

### Key improvements

1. **Constructor vs post-set attributes** — Prefer adding optional `remaining_quantity` and `remaining_margin_used` as **attr_accessor** set after `new(...)` so existing `build_one_leg` / `build_one_aggregate` call sites stay unchanged. Override `open_quantity` and `margin_used` with methods that return these when set, else the current logic (so `attr_reader :margin_used` becomes a method).
2. **Sort order** — Use `close_at = last_trade.executed_at` (most recent trade in the position, typically the last close) for the remainder row so it sorts next to that position’s closed legs; consistent with existing close_at desc sort and keeps balance order correct.
3. **Commission for remainder row** — With `trades = [open_trade]`, `total_commission` would return the open trade’s fee. Decide whether to show 0 (remainder is “open” only) or that fee; document in implementation to avoid double-counting with closed leg row(s).
4. **Multiple partial closes** — One remainder row per position (open_qty - total closed_qty) is correct; no need for a row per close. Sum closed_qty across all closing legs when computing remaining_qty.

### New considerations

- **total_commission:** Remainder row’s `trades` is `[open_trade]`; current `total_commission` sums all trades’ fees. Either show 0 for remainder (recommended: no commission on “open” side) or leave as open_trade.fee and accept that the open fee appears only on the remainder row (closed leg row already shows close_trade fee). Recommend 0 for remainder for clarity.
- **effective_margin_for_roi:** Only used by `roi_percent` (realized). Remainder row uses `unrealized_roi_percent` and `margin_used` directly; no change needed.

---

## Overview

When a position is **partially closed** (e.g. open 1 BNB, close 0.5 BNB), the trades table currently shows only one row per **closing leg**. The **remaining open** quantity (e.g. 0.5 BNB) is not shown, so users see the closed portion but not the open remainder. This plan adds one row per position for the "remaining open" when `open_quantity > closed_quantity`, so both the closed leg(s) and the open remainder appear, with unrealized PnL/ROI for the remainder when current price is available.

**Context:** Todo 012; original open-trades plan (2026-03-03) had "remaining open after partial close" out of scope. This plan implements that follow-up.

---

## Problem Statement / Motivation

- Partially closed positions (e.g. BNB half closed on 2026-01-30, $4.77 margin on the closed leg) currently produce only rows for each **closed** leg. The remaining open quantity does not appear as an open trade.
- Users expect to see both: (1) the closed leg(s) with realized PnL/ROI, and (2) the remaining open position with unrealized PnL/ROI.
- Today, only **fully** open positions (no closing leg) show as "Open"; partial closes are under-reported.

---

## Proposed Solution

1. **In `PositionSummary.build_summaries`:** When there are closing legs, after building one row per closing leg (existing behavior), check whether `open_quantity > closed_quantity` for that position. If so, build **one additional** summary row representing the "remaining open" quantity.
2. **Remainder row semantics:**
   - Same symbol, exchange_account, leverage, open_at; same opening trade for entry price and side.
   - **margin_used** = opening margin × (remaining_qty / open_qty), where remaining_qty = open_quantity - closed_quantity.
   - **net_pl** = 0 (no realized PnL for the remainder), so running balance is unchanged.
   - **close_at** = last trade’s executed_at (for sorting) or a sentinel so the row sorts with open positions; row is displayed as "Open".
   - Row must be treated as **open** (`open?` true) so the view shows "Open" and unrealized PnL/ROI when current price is available.
3. **Unrealized PnL/ROI:** Use the same formulas as for fully open positions, but with **remaining quantity** and the remainder’s **margin_used**. Entry price comes from the opening trade.
4. **Balance:** `assign_balance!` sums `net_pl`; remainder row has `net_pl = 0`, so no double-counting. Existing balance semantics unchanged.
5. **Sorting:** Remainder row participates in the same sort (e.g. by close_at desc). Decide whether to use last fill time or a fixed "open" timestamp so it appears in a sensible place (e.g. with other open rows).

---

## Technical Considerations

- **PositionSummary structure:** Today each summary has `trades` (array) and derives `open_quantity` / `closed_quantity` from those trades. A remainder row does not have a "subset" of trades that represents only the remaining qty; it shares the same opening trade. Options: (a) Add optional attributes (e.g. `remaining_quantity`, `remaining_margin_used`) set only for remainder rows; `open_quantity` and `margin_used` return these when set, else current logic. (b) Build the remainder row with a copy of the open trade and a synthetic "remaining" representation. Recommendation: (a) to avoid changing the meaning of `trades` and to keep a single code path for `open?`, `entry_price`, `unrealized_pnl`, `unrealized_roi_percent` when we pass remaining qty/margin where needed.
- **open?:** Remainder row must be considered open. If we use optional attributes, we can treat "has remaining_quantity?" as open for display and unrealized; or keep `trades` as [open_trade] only (no closing trades) so existing `open?` (trades.none? { closing_leg?(t) }) is true.
- **Entry price:** Same as opening trade (avgPrice or notional/qty). No change.
- **Unrealized PnL/ROI:** Must use remaining_qty and remainder margin. Either override `open_quantity` and `margin_used` for this row, or pass remaining qty/margin into the existing methods (e.g. optional args or instance attributes). Prefer instance attributes set at build time so the view and IndexService need no changes.
- **assign_balance!:** No change; remainder row has net_pl = 0.
- **TickerFetcher:** No change; open-position symbols already collected from positions with `open?` true; remainder row will be open? true so its symbol will be included for price fetch.
- **View:** No change; view already uses `pos.open?`, `pos.unrealized_pnl(@current_prices[pos.symbol])`, `pos.unrealized_roi_percent(...)`. As long as the remainder row reports open? and the right margin/qty for unrealized, the view works.

### Research insights (Technical)

**Attribute override without changing constructor**

- `PositionSummary` uses `attr_reader :margin_used` and a method `open_quantity`. To support remainder rows without a second constructor or optional kwargs everywhere, add `attr_accessor :remaining_quantity, :remaining_margin_used` (default nil). After building the remainder with `new(trades: [open_trade], ..., margin_used: remainder_margin, net_pl: 0)`, set `summary.remaining_quantity = remaining_qty` and `summary.remaining_margin_used = remainder_margin`. Then change `margin_used` from attr_reader to a method: `def margin_used; @remaining_margin_used.presence || @margin_used; end` (store the “base” margin in an ivar set in initialize). Similarly `open_quantity` returns `@remaining_quantity` when set, else derives from trades.first. That way `build_one_leg` and `build_one_aggregate` stay as-is.
- **Alternative:** Add optional kwargs `remaining_quantity: nil, remaining_margin_used: nil` to `initialize` and set ivars; then `open_quantity` and `margin_used` read those when present. Keeps one constructor; all builders pass the same args (remainder passes the overrides). Slightly more explicit than post-set.

**Sort order**

- `from_trades` sorts by `close_at` desc. Use the position’s **last trade** `executed_at` as the remainder row’s `close_at` so it sorts next to that position’s most recent activity (usually the last close). Avoids a separate “open” sentinel and keeps pagination/balance order consistent.

**Commission**

- For remainder row, `trades = [open_trade]` so `total_commission` would currently return `open_trade.fee`. Showing that fee only on the remainder (and not on closed legs) is acceptable; alternatively define remainder rows to report commission 0 so the open fee is not shown on the “Open” row. Recommend 0 for remainder to avoid confusion (closed leg row already shows the closing commission).

**Multiple partial closes**

- Sum `closed_qty` across all closing trades in the position. `remaining_qty = open_qty - total_closed_qty`. One remainder row per position; no row per close.

---

## Acceptance Criteria

- [x] For any position with `open_quantity > closed_quantity`, the trades table shows one additional row for the remaining open quantity, with "Open" in the Closed column and unrealized PnL/ROI when current price is available (and "—" when not).
- [x] Running balance is unchanged: remainder row contributes net_pl = 0 to the running balance.
- [x] Existing behavior for fully open positions (no closing leg) and fully closed positions is unchanged.
- [x] Margin and ROI for the remainder row use the proportional margin (open margin × remaining_qty / open_qty) and unrealized PnL/ROI based on remaining quantity.
- [x] Unit tests: PositionSummary builds a remainder row when position has closing legs and open_quantity > closed_quantity; remainder row has open? true, net_pl 0, and correct proportional margin. Request test: partially closed position shows two rows (one closed leg, one "Open" remainder) when applicable.
- [x] No remainder row when open_quantity == closed_quantity (fully closed). Commission for remainder row defined (e.g. 0 or —).

---

## Success Metrics

- Users see both closed leg(s) and remaining open for partially closed positions.
- No regression in balance or in fully open / fully closed display.

---

## Dependencies & Risks

- **Dependencies:** Builds on open-trades unrealized PnL (current price fetch, open?, unrealized_pnl/roi_percent). No new external dependencies.
- **Risks:** (1) Sort order for remainder row (close_at) must be consistent so pagination and balance order remain correct. (2) Edge case: multiple partial closes (e.g. close 0.3, then 0.2) — we still have one "remaining open" for (open_qty - total closed_qty); no need for multiple remainder rows per position.

### Research insights (Risks)

- **Rounding:** Use same rounding as `build_one_leg` (e.g. `.round(8)` for margin and qty ratios) so remainder margin matches exchange semantics. Avoid floating point for ratios; use `BigDecimal` and `to_d` where applicable.
- **Fully closed edge:** When `open_quantity == closed_quantity` (e.g. two legs that sum to open), do not emit a remainder row; existing logic (only closing legs) is correct.

---

## Implementation outline

1. **PositionSummary**
   - Add `attr_accessor :remaining_quantity, :remaining_margin_used`. Replace `attr_reader :margin_used` with a method that returns `@remaining_margin_used.presence || @margin_used` (keep setting `@margin_used` in initialize). Update `open_quantity` to return `@remaining_quantity` when set, else current logic. For remainder row, set `closed_quantity` behavior: with `trades = [open_trade]`, `closed_quantity` is already 0 (no closing legs in trades), so no change needed.
   - In `build_summaries`, after `closing.map { build_one_leg(...) }`, compute open_qty and total closed_qty (sum over all closing trades). If open_qty > total_closed_qty: remaining_qty = open_qty - total_closed_qty; remainder_margin = open_margin * (remaining_qty / open_qty).round(8). Build remainder with `new(trades: [open_trade], exchange_account:, symbol:, leverage:, open_at: first.executed_at, close_at: last.executed_at, margin_used: remainder_margin, net_pl: 0)`, then set `summary.remaining_quantity = remaining_qty` and `summary.remaining_margin_used = remainder_margin`. Append to the list. Use last = position_trades.last (most recent trade) for close_at.
   - **Commission:** Override `total_commission` for remainder rows to return 0 (or leave as open_trade.fee; document choice). Easiest: when `remaining_quantity` is set, `total_commission` returns 0.
   - `entry_price`, `unrealized_pnl`, `unrealized_roi_percent` already use `open_quantity` and `margin_used`; once those return the remainder overrides, no further change.
2. **assign_balance!**  
   No change; remainder has net_pl 0.
3. **Tests**
   - Unit: build_summaries with one open trade and one closing trade (partial: close_qty < open_qty) returns two summaries: one build_one_leg (closed), one remainder (open?, net_pl 0, proportional margin). Optionally test unrealized_pnl for remainder row with stubbed price.
   - Request: Create a partial-close position (open + one close with qty < open qty); get trades index; assert two rows for that symbol, one with "Open" and one with close date.
4. **View / IndexService**  
   No change expected; verify with manual or request test.

---

## References & Research

- Todo: todos/012-pending-p2-remaining-open-after-partial-close.md
- Plan (open trades): docs/plans/2026-03-03-feat-open-trades-unrealized-pnl-plan.md (Partial closes out of scope)
- Implementation: app/models/position_summary.rb (build_summaries, build_one_leg, build_one_aggregate, open_quantity, closed_quantity, assign_balance!, open?, unrealized_pnl, unrealized_roi_percent)
