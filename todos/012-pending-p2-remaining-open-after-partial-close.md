# Show "remaining open" row after partial close

- **status:** pending
- **priority:** p2
- **issue_id:** 012
- **tags:** code-review, feature, position-summary
- **dependencies:** none

## Problem Statement

Positions that are **partially closed** (e.g. open 1 BNB, close 0.5 BNB) currently produce only one row per **closing leg** in the trades table. The **remaining open** quantity (e.g. 0.5 BNB still open) is not shown as an open row, so it looks like the position is fully closed. Users expect to see both the closed leg(s) and the remaining open position.

**Observed:** User has (1) short BTC 20.3 USD margin — shows as Open ✓ (2) BNB position, half closed on 2026-01-30, $4.77 margin on the closed leg — only the closed leg appears; the remaining open BNB does not appear as an open trade.

## Findings

- **Location:** `app/models/position_summary.rb`, `build_summaries`.
- **Current behavior:** If `closing.empty?` → one row (open). If there are closing legs → one row **per closing trade** via `build_one_leg`; no row is built for `open_quantity - closed_quantity`.
- **Root cause:** By design in the original plan: "Remaining open after partial close is out of scope."
- **Impact:** Partially closed positions are under-reported in the "open" view; only fully open positions (no closing leg) show as "Open."

## Proposed Solutions

1. **Add a "remaining open" row when open_quantity > closed_quantity (recommended)**  
   After building rows for each closing leg, if `open_quantity > closed_quantity`, build one additional summary row for the remainder: same symbol/account/leverage, margin_used proportional to (open_qty - closed_qty)/open_qty, close_at = nil or last fill time, mark as open so it gets unrealized PnL/ROI.  
   **Pros:** Matches user expectation; one more row per partially closed position. **Cons:** Need to avoid double-counting in balance (remainder row net_pl = 0 or only fees). **Effort:** Medium. **Risk:** Low if balance logic excludes unrealized from running balance.

2. **Show a badge or note on closed legs**  
   e.g. "Partial (0.5 open)" on the BNB closed row, with no separate open row.  
   **Pros:** Small change. **Cons:** Does not show remaining open in the table or in open count. **Effort:** Small. **Risk:** Low.

3. **Leave as-is and document**  
   Keep current behavior; add help text that "only fully open positions appear as Open; partial closes show only the closed portion."  
   **Pros:** No code change. **Cons:** User confusion. **Effort:** Small. **Risk:** None.

## Recommended Action

Implement Solution 1 when prioritised: add one row per position for "remaining open" when `open_quantity > closed_quantity`, with `open?` true and unrealized PnL/ROI when current price is available. Ensure running balance remains based on realized PnL only (open row contributes 0 to balance).

## Technical Details

- **Affected files:** `app/models/position_summary.rb` (build_summaries, possibly a new method like `build_remaining_open_aggregate`), view if we need to distinguish "fully open" vs "remaining open" (optional).
- **Balance:** Remainder row should have `net_pl` = 0 (or sum of fees only) so `assign_balance!` does not double-count realized PnL.
- **Unrealized:** Use same `entry_price` / `unrealized_pnl` / `unrealized_roi_percent` with remaining qty and proportional margin.

## Acceptance Criteria

- [ ] For any position with open_quantity > closed_quantity, the trades table shows one additional row for the remaining open quantity, with "Open" and unrealized PnL/ROI when price is available.
- [ ] Running balance is unchanged (remaining open row does not add realized PnL).
- [ ] Existing behavior for fully open and fully closed positions is unchanged.

## Work Log

- 2026-03-03: User reported only one open trade (BTC) visible; BNB half-closed (2026-01-30, $4.77 margin) only shows as closed leg. Root cause: remaining open not emitted by build_summaries. Added todo for future "remaining open" support.

## Resources

- Plan: docs/plans/2026-03-03-feat-open-trades-unrealized-pnl-plan.md (Partial closes out of scope)
- Implementation: app/models/position_summary.rb (build_summaries, build_one_leg, open_quantity, closed_quantity)
