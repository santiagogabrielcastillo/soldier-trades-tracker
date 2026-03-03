# Open Trades with Unrealized PnL / ROI — Brainstorm

**Date:** 2026-03-03  
**Scope:** Show open positions in the same trades table with unrealized PnL and ROI, using current price fetched only on page load.

---

## What We're Building

1. **Open trades in the same table**  
   Keep the existing positions table. Rows that represent open positions (no closing leg yet) are visually distinguished (e.g. "Open" in the date column or a badge). They show the same attribute columns: margin used, ROI, net PnL, etc. For open rows, **unrealized** PnL and ROI are computed using the **current price** of the traded pair.

2. **Current price on page load only**  
   When the trades page is loaded, the app fetches the current price for each unique symbol that has an open position. No automatic polling, no background refresh—price is fetched (or recalculated) only on full page reload. If price is unavailable, show "—" or "n/a" for unrealized metrics.

3. **Same formulas, different inputs**  
   Unrealized PnL and unrealized ROI reuse the same logic as closed trades (margin-based ROI, direction-aware PnL) but use current market price instead of close price. Open positions already have margin_used and open quantity from existing `PositionSummary` / `Trade` data; we add a current-price source and derive unrealized values.

4. **Filters later**  
   Filters (e.g. "All | Open | Closed") are out of scope for this feature and will be added in a follow-up.

---

## Why This Approach

- **Single source of truth:** One table for all positions; users see both closed and open in one place with consistent columns.
- **YAGNI:** No separate Open tab or filter UI in this iteration; can add filters later.
- **Simple refresh model:** Fetch price only on page load avoids polling, WebSockets, or background jobs for ticker data. Aligns with "no automatic fetching initially."
- **Reuse:** `PositionSummary` already identifies open positions (no closing leg); we extend with current price and unrealized calculations rather than a new structure.

---

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Where to show open trades | Same table as closed, with visual distinction | Single list; same attributes (margin, ROI, PnL); minimal UI change. |
| When to fetch current price | On page load only | No polling or auto-refresh; user reloads to get fresh prices. |
| Price source | Exchange public ticker (e.g. BingX) per symbol | No auth needed for ticker; one request per symbol with open positions. |
| Unrealized metrics | Unrealized PnL, unrealized ROI for open rows | Same semantics as closed (ROI = PnL / effective margin × 100); "—" if price missing. |
| Filters (Open / Closed) | Later | Deferred; add in a follow-up. |

---

## Resolved Questions

- **Same table vs separate tab?** → Same table (Approach 1); filters later.
- **Automatic price refresh?** → No; only on page reload.

---

## Open Questions

None that block implementation. (Filters and any future "refresh" button are follow-ups.)
