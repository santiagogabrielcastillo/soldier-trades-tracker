---
title: Spot portfolio cash position (USDT)
type: feat
status: completed
date: 2026-03-14
---

# Spot portfolio cash position (USDT)

## Enhancement Summary

**Deepened on:** 2026-03-14  
**Sections enhanced:** Proposed solution (1–6), Technical considerations, Acceptance criteria, Edge cases  
**Research sources:** Rails validation/enum patterns, Stimulus conditional form fields, financial app division-by-zero edge cases, Rails/data-integrity review conventions.

### Key improvements

1. **Validation:** Keep explicit `inclusion: { in: %w[buy sell deposit withdraw] }` (no Rails enum) so existing code and CSV flow stay simple; no DB enum type needed for one new feature.
2. **Conditional form:** Use a small Stimulus controller with a `change` listener on Side; toggle visibility of Price and Token (e.g. `hidden` or CSS class) when value is `deposit` or `withdraw`; support multiple conditional blocks with a `showIf`-style value.
3. **Division by zero:** Always guard cash %: `total_portfolio.positive? ? (cash_balance / total_portfolio * 100).round(2) : nil` (or 0); display "—" when nil. Prevents Firefly III–style dashboard errors when net worth/portfolio is zero.
4. **Data integrity:** No migration required; `row_signature` uniqueness remains per spot_account_id. Cash entries use a distinct prefix (`cash|...`) so they never collide with CSV-derived signatures. Keep CSV import strictly buy/sell so no invalid sides enter via import.

### New considerations

- **Negative cash balance:** If withdrawals exceed deposits, cash_balance can be negative. Decide display (e.g. red, or "−$X") and whether to allow negative in validation or only warn in UI.
- **Stimulus accessibility:** When hiding Price/Token for deposit/withdraw, use `hidden` or `aria-hidden` so required state is clear for screen readers; avoid removing fields from DOM so server still receives a value if JS fails (or send token/price from controller defaults only).

---

## Overview

Track USDT cash held in the spot portfolio via **deposit** and **withdraw** transactions. Cash balance does not affect ROI or cost basis. Show **cash balance** and **cash % of portfolio** on the dashboard (Spot section) and on the spot portfolio view. Context and decisions from the [2026-03-14 brainstorm](docs/brainstorms/2026-03-14-spot-cash-position-brainstorm.md).

## Problem statement / motivation

- Users hold USDT (or other stablecoin) on the same exchange as spot; that cash is part of their portfolio but not reflected in the app.
- ROI and PnL should remain based only on crypto positions; cash is informational.
- Users need to see what share of their spot portfolio is cash (e.g. “20% cash”) on the dashboard and on the spot page.

## Proposed solution

### 1. Extend spot_transactions with deposit/withdraw

- **Model:** Allow `side` in `%w[buy sell deposit withdraw]` on `SpotTransaction`. No new table; no migration if `side` is already a string (existing schema supports new values).
- **Cash rows:** For deposit/withdraw: `token` = `"USDT"`, `price_usd` = 1, `total_value_usd` = amount. `row_signature` must be unique: use a distinct format for cash (e.g. `"cash|#{executed_at.to_i}|#{SecureRandom.hex(8)}"`) so manual cash entries never collide with each other or with CSV-imported buy/sell rows.
- **PositionStateService:** Only consider buy/sell when building positions. Use a scope `SpotTransaction.trades` (where side in buy/sell) or filter inside the service so deposit/withdraw are ignored for positions, cost basis, and ROI.
- **Cost basis chart:** `spot_cost_basis_series` in `Dashboards::SummaryService` must iterate only buy/sell transactions (exclude deposit/withdraw) so the chart reflects trading cost basis only.

**Research insights (model and scope):**

- **Validation:** Prefer explicit `validates :side, inclusion: { in: %w[buy sell deposit withdraw] }` over Rails enum for a string column when you are only adding two values and want to avoid enum API surface and keep CSV/controller logic unchanged. Rails 7.1+ enum with `validate: true` is an alternative if you later want scopes and bang methods.
- **Scope naming:** A named scope `scope :trades, -> { where(side: %w[buy sell]) }` makes call sites self-documenting and keeps PositionStateService and cost_basis_series unchanged in intent.
- **Data integrity:** No migration; existing `row_signature` unique index stays. Cash rows use a different signature format (e.g. `"cash|#{executed_at.to_i}|#{SecureRandom.hex(8)}"`) so they never conflict with `CsvRowParser` output. CSV import must continue to validate side in `%w[buy sell]` only.

### 2. Cash balance and cash %

- **Cash balance:** Sum of (deposit amounts) − sum of (withdraw amounts) for the spot account. Implement as `SpotAccount#cash_balance` or a small `Spot::CashBalanceService`; used by dashboard and spot index.
- **Total portfolio:** `spot_value` (crypto positions at current price) + `cash_balance`.
- **Cash %:** `cash_balance / total_portfolio * 100` when `total_portfolio > 0`; otherwise 0 or "—".

**Research insights (cash balance and %):**

- **Division by zero:** Financial apps (e.g. Firefly III, portfolio dashboards) frequently hit division-by-zero when total portfolio or net worth is zero. Always guard: `total_portfolio.positive? ? (cash_balance / total_portfolio * 100).round(2) : nil`; in the view show "—" when nil. Never divide by `total_portfolio` without a positive check.
- **Negative cash:** If withdrawals exceed deposits, `cash_balance` can be negative. Decide whether to allow it (e.g. for corrections) and how to display (e.g. red, "−$X"). No change to formula: cash % can be negative when total_portfolio is positive.
- **Placement of logic:** Implementing `SpotAccount#cash_balance` (e.g. `spot_transactions.where(side: 'deposit').sum(:amount) - spot_transactions.where(side: 'withdraw').sum(:amount)`) keeps the rule in one place; dashboard and spot index both call it. Alternative: small `Spot::CashBalanceService.call(spot_account:)` if you prefer a service over model logic.

### 3. New transaction form (Portfolio tab)

- **Single form:** Side = Buy | Sell | Deposit | Withdraw (add Deposit and Withdraw to the select).
- **When Side is Deposit or Withdraw:** Hide Price (USD) and Token (or fix Token to USDT and hide/disable). Only Amount and Date & time are required. On submit, controller sets token = "USDT", price_usd = 1, total_value_usd = amount, and generates cash row_signature.
- **UX:** Use a small Stimulus controller to show/hide Price and Token based on Side (or optional server-rendered conditional markup). Ensure validation allows deposit/withdraw with token and price defaulted server-side.

**Research insights (conditional form):**

- **Stimulus pattern:** Use a controller with a target on the Side select and targets on the Price and Token wrappers. On `change`, if value is `deposit` or `withdraw`, set wrapper `hidden = true` (or add a `hidden` CSS class); otherwise set `hidden = false`. Use `data-action="change->spot-transaction-form#togglePriceAndToken"` on the select. No need for a separate "showIf" value if you only have two cases; a single `["deposit", "withdraw"].includes(value)` check is enough.
- **Accessibility:** Prefer the `hidden` attribute or a class that hides visually and from a11y tree, so required state is clear. If you keep the fields in the DOM but hidden, ensure server-side defaults (token=USDT, price_usd=1) are applied when side is deposit/withdraw so submission works even if JS is off (optional: disable or clear Price/Token when hidden so they are not submitted with stale values).
- **References:** [Stimulus show/hide based on select](https://discuss.rubyonrails.org/t/turbo-stimulus-show-hide-form-fields-based-on-the-value-of-a-select/84862), [conditional form with Stimulus](https://blog.corsego.com/stimulus-display-show-hide-div-based-on-value).

### 4. Transactions list (Transactions tab)

- **Filter:** Extend side filter to allow `deposit` and `withdraw` (e.g. Side: All | Buy | Sell | Deposit | Withdraw). Controller permits and applies `params[:side]` when in `%w[buy sell deposit withdraw]`.
- **Table:** Same columns as today (Date, Token, Side, Amount, Price (USD), Total value (USD)). For deposit/withdraw rows: Token = USDT, Price = "—" (or N/A), Amount and Total value as stored. Row styling: deposit similar to buy (e.g. green tint), withdraw similar to sell (e.g. red tint).

### 5. Dashboard Spot section

- Add **Cash balance** (formatted as money) and **Cash %** (e.g. "20.5%") to the Spot block. Total portfolio = spot_value + cash_balance; cash % = cash_balance / total_portfolio when total_portfolio > 0.
- `Dashboards::SummaryService#spot_summary` already returns spot_value, etc.; add `spot_cash_balance` and `spot_cash_pct` (and optionally `spot_total_portfolio` if useful). When there are no open positions, spot_value can be 0; cash_balance and cash_pct still computed from cash movements.

**Research insights (dashboard):**

- **Cash % in summary:** Compute once in the service: `total = spot_value + cash_balance; spot_cash_pct = total.positive? ? (cash_balance / total * 100).round(2) : nil`. In the view, use `@dashboard.spot_cash_pct.nil? ? "—" : "#{number_with_precision(@dashboard.spot_cash_pct, precision: 2)}%"` to avoid any division in the view layer.

### 6. Spot portfolio view (Portfolio tab)

- Above the positions table (or in a small summary row), show **Cash balance** and **Cash %** using the same formula. `SpotController#load_index_data` (or a helper) computes `@cash_balance`, `@spot_value` (sum of open position values), `@total_portfolio`, `@cash_pct` and passes them to the view.

**Research insights (portfolio tab):**

- Reuse the same formula as dashboard so behavior is consistent: `total = spot_value + cash_balance; cash_pct = total.positive? ? (cash_balance / total * 100).round(2) : nil`. Display "—" when `cash_pct.nil?`. Keeps one source of truth (e.g. SpotAccount#cash_balance) and one formula in two places (dashboard service + spot controller or shared helper).

## Technical considerations

- **CSV import:** Remain buy/sell only. `Spot::CsvRowParser` and import service do not create deposit/withdraw; no change to CSV format or row_signature for imported rows.
- **Validation:** `SpotTransaction` validates `side` inclusion in `%w[buy sell deposit withdraw]`. For deposit/withdraw, `price_usd` and `total_value_usd` are still required; set in controller before build/save.
- **PositionStateService:** Use `@spot_account.spot_transactions.trades.ordered_by_executed_at` (add `scope :trades, -> { where(side: %w[buy sell]) }` on SpotTransaction) so deposit/withdraw are never fed into position or cost basis logic.
- **spot_cost_basis_series:** Iterate only `spot_account.spot_transactions.trades.ordered_by_executed_at` so the running cost basis excludes cash movements.
- **Tests:** Add unit tests for SpotAccount#cash_balance (or equivalent); SpotTransaction validation for deposit/withdraw; PositionStateService and spot_cost_basis_series ignoring deposit/withdraw; controller create with deposit/withdraw; dashboard and spot index show cash and %.

**Research insights (technical):**

- **Rails conventions:** Prefer extracting the cash-creation branch in `SpotController#create` into a small private method (e.g. `build_cash_transaction(permitted)`) rather than inflating the main create action; keeps "existing code modifications" strict per Rails review habits.
- **CSV boundary:** Do not add deposit/withdraw to `Spot::CsvRowParser` or import; keep import strictly buy/sell so CSV format and row_signature semantics stay unchanged and no invalid sides enter via file upload.

## Acceptance criteria

### Model and data

- [x] `SpotTransaction` accepts `side` in `%w[buy sell deposit withdraw]`; CSV import and existing buy/sell flows unchanged.
- [x] Cash balance = sum(deposit amounts) − sum(withdraw amounts) per spot account; ROI and cost basis exclude deposit/withdraw (PositionStateService and cost basis chart use only buy/sell).

### New transaction form

- [x] "New transaction" form includes Side: Buy, Sell, Deposit, Withdraw. When Deposit or Withdraw is selected, Price (and optionally Token) are hidden or fixed; user enters Amount and Date. Submitting creates a row with token=USDT, price_usd=1, total_value_usd=amount.

### Transactions list

- [x] Transactions tab filter Side includes Deposit and Withdraw. Table shows deposit/withdraw rows with same columns; Price shows "—" for those rows; Token shows USDT. Deposit/withdraw rows have distinct row styling (e.g. deposit = green tint, withdraw = red tint).

### Dashboard

- [x] Spot section shows Cash balance (formatted) and Cash % (e.g. "X.X%"). Total portfolio = spot value + cash balance; cash % = cash / total portfolio when total > 0.

### Spot portfolio view (Portfolio tab)

- [x] Portfolio tab shows Cash balance and Cash % (same formula) above or beside the positions table.

### Edge cases

- [x] No cash movements: cash balance 0, cash % 0 or "—". No positions and no cash: total portfolio 0, cash % handled without division by zero.
- [x] Only cash (no open positions): spot_value 0, total portfolio = cash_balance, cash % = 100%.
- [x] **Division by zero:** Cash % calculation never divides when `total_portfolio <= 0`; return `nil` and display "—" in UI (per financial-app best practice; see Firefly III / portfolio dashboard issues).
- [x] **Negative cash balance:** If withdrawals > deposits, cash_balance is negative; display consistently (e.g. red or "−$X") and ensure percentage formula still works (negative % when total > 0).

## Files to touch (implementation hints)

| Area | File(s) |
|------|--------|
| Model | `app/models/spot_transaction.rb` (side inclusion; scope `trades`) |
| Cash balance | `app/models/spot_account.rb` (e.g. `cash_balance`) or `app/services/spot/cash_balance_service.rb` |
| Positions / chart | `app/services/spot/position_state_service.rb` (use `trades` only); `app/services/dashboards/summary_service.rb` (spot_summary: add cash_balance, cash_pct; spot_cost_basis_series: use trades only) |
| Create flow | `app/controllers/spot_controller.rb` (create: accept deposit/withdraw; set token, price_usd, row_signature for cash) |
| Filters / list | `app/controllers/spot_controller.rb` (load_spot_transactions_filtered: allow side in deposit/withdraw); `app/views/spot/index.html.erb` (transactions table: Price "—" for cash; side filter options; row class for deposit/withdraw) |
| New transaction form | `app/views/spot/index.html.erb` (Side select + Deposit/Withdraw; conditional Price/Token); optional `app/javascript/controllers/spot_transaction_form_controller.js` (toggle visibility by side) |
| Dashboard | `app/views/dashboards/show.html.erb` (Spot section: Cash balance, Cash %) |
| Spot portfolio summary | `app/controllers/spot_controller.rb` (load_index_data: set @cash_balance, @spot_value, @total_portfolio, @cash_pct); `app/views/spot/index.html.erb` (portfolio tab: display cash and %) |
| Tests | `test/models/spot_transaction_test.rb`; `test/models/spot_account_test.rb` (or service test); `test/services/spot/position_state_service_test.rb`; `test/services/dashboards/summary_service_test.rb`; `test/controllers/spot_controller_test.rb` |

## References

- Brainstorm: [docs/brainstorms/2026-03-14-spot-cash-position-brainstorm.md](docs/brainstorms/2026-03-14-spot-cash-position-brainstorm.md)
- Existing spot summary: `app/services/dashboards/summary_service.rb` (`spot_summary`, `spot_cost_basis_series`)
- Spot create and filters: `app/controllers/spot_controller.rb` (`create`, `load_spot_transactions_filtered`)
- Position state: `app/services/spot/position_state_service.rb` (only buy/sell today)
