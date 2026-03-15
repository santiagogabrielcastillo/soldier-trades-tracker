# Spot Portfolio — Cash Position (USDT) Brainstorm

**Date:** 2026-03-14  
**Scope:** Track USDT cash held in the spot portfolio via deposit/withdraw transactions; show cash balance and % of portfolio as cash on dashboard and spot portfolio view. Cash does not affect ROI or cost basis.

---

## What We're Building

- **Cash balance:** User can record “Deposit USDT” and “Withdraw USDT” movements. Cash balance = sum of deposits minus sum of withdrawals (one currency: USDT).
- **ROI unchanged:** Cost basis, unrealized PnL, and ROI are computed only from buy/sell positions (existing logic). Cash is excluded from position and ROI calculations.
- **Display:**
  - **Dashboard (Spot section):** Show cash balance and **cash %** of total spot portfolio. Total portfolio = spot value (crypto positions) + cash. Cash % = cash / total portfolio × 100.
  - **Spot portfolio view:** Same: show cash balance and cash % (e.g. in the summary row or above the positions table).
- **Transactions list:** Deposit and withdraw entries appear in the same Transactions tab (with buy/sell), so all activity is in one list. Filter by side can include “Deposit” and “Withdraw”.

---

## Approach A: Extend spot_transactions with deposit/withdraw (recommended)

**Description:** Add `deposit` and `withdraw` to the allowed `side` values on `SpotTransaction`. For these, token is USDT, amount is the USDT amount, price_usd = 1, total_value_usd = amount. `PositionStateService` and cost basis / ROI logic only consider `buy`/`sell`. Cash balance is computed as sum of (deposit amount) − sum of (withdraw amount) for the spot account. Transactions list already shows all rows; add “Deposit” and “Withdraw” to the side filter.

**Pros:** One table, one list, no new models or routes for “activity”; reuse existing transactions UI and filters.  
**Cons:** Same table mixes trades and cash movements; CSV import and row_signature must stay buy/sell-only (cash entries get a distinct signature format so they don’t collide).

**Best for:** Keeping a single source of truth and minimal new concepts; YAGNI.

---

## Approach B: Separate spot_cash_movements table

**Description:** New model `SpotCashMovement` (e.g. spot_account_id, amount, direction: deposit/withdraw, executed_at, optional note). Cash balance = sum of movements. Spot transactions stay buy/sell only. Cash movements are shown either in a separate “Cash” section on the portfolio tab or in a combined “Activity” list that merges trades and cash (two data sources).

**Pros:** Clear separation; no change to `SpotTransaction` validation or CSV; cash semantics are explicit.  
**Cons:** Two places to look unless we build a unified activity view; more models, routes, and UI surface.

**Best for:** If you want cash to be a first-class, clearly separated ledger that might later support multiple cash currencies or more metadata.

---

## Recommendation

**Approach A (extend spot_transactions).** One list for all activity, one place to filter by type (buy/sell/deposit/withdraw), and no new tables. ROI and position logic stay unchanged by only processing buy/sell. Cash % is a derived metric (cash / (spot_value + cash)) in the dashboard and spot summary. If we later need a separate cash ledger or multi-currency cash, we can introduce a dedicated model and migrate.

---

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| How to record cash | Deposit/withdraw as transactions (user chose option 2) | Balance is auditable from movements; appears in transaction list. |
| Where to store cash movements | Approach A: same `spot_transactions` table, new sides | Single list, minimal new concepts; ROI and positions ignore non–buy/sell. |
| Cash % formula | cash / (spot_value + cash) × 100 | Total portfolio = crypto value + cash; percentage is cash share of total. |
| ROI / cost basis | Exclude deposit/withdraw | User requirement: cash does not affect ROI. |
| Where to show cash and % | Dashboard Spot section + Spot portfolio view | User requirement: visible in both places. |

---

## Open Questions

_None._

---

## Resolved Questions

- **How to record USDT balance:** Cash movements as transactions (deposit/withdraw), not a single editable number.
- **Transactions list for deposit/withdraw:** Same columns as buy/sell; use "—" or N/A where not applicable (Token = USDT, Price = "—").
- **New transaction form:** Single form with Side = Buy | Sell | Deposit | Withdraw; when Deposit or Withdraw, hide Price (and optionally Token), only Amount + date.

---

## Summary

- Track USDT cash via **deposit** and **withdraw** transactions in the same spot transaction list (extend `side` to include deposit/withdraw; PositionStateService and ROI ignore them).
- **Cash balance** = sum(deposits) − sum(withdrawals). **Cash %** = cash / (spot_value + cash) × 100.
- Show **cash balance** and **cash %** on the dashboard (Spot section) and on the spot portfolio view.
- ROI and cost basis remain based only on buy/sell positions.

Next: Run `/plan` to implement.
