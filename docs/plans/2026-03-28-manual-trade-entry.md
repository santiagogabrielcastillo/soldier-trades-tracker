---
title: "feat: Manual Trade Entry for historical crypto futures trades"
type: feat
status: draft
date: 2026-03-28
---

# feat: Manual Trade Entry

## Overview

Some historical trades are too old to be fetched from the BingX/Binance exchange APIs.
This feature adds a form on the Exchange Accounts index page that lets users create
trades manually. Manually-created trades flow through the same `Positions::RebuildForAccountService`
and `PositionSummary` pipeline as synced trades, so positions are rebuilt correctly.

Manual trades are identified by an `exchange_reference_id` starting with `"manual_"`.
Edit and delete are restricted to manual trades. A visual badge in the trades index
distinguishes manual entries from exchange-synced ones.

## Raw Payload Shape (BingX format)

`PositionSummary` reads the following keys from `raw_payload`. The synthetic payload
for manual trades must include all of them so the existing pipeline works unchanged:

```json
{
  "side":         "BUY",
  "executedQty":  "0.5",
  "avgPrice":     "42000.0",
  "positionSide": "LONG",
  "reduceOnly":   false,
  "leverage":     "10X",
  "positionID":   "manual_pos_<timestamp>_<random>",
  "profit":       "0.0"
}
```

Key method dependencies:
- `leverage_from_raw` reads `raw["leverage"]` (strips trailing `X`)
- `notional_from_raw` reads `raw["avgPrice"]` and `raw["executedQty"]`
- `realized_profit_from_raw` reads `raw["profit"]`
- `reduce_only?` checks `raw["reduceOnly"] == true`
- `position_side` reads `raw["positionSide"]`
- `position_id` column on Trade is set to `raw["positionID"]` value

## Computed Fields

- `net_amount`: `qty * price`. Positive for sell (funds received), negative for buy (funds spent).
- `exchange_reference_id`: `"manual_#{timestamp_ms}_#{SecureRandom.hex(4)}"` — unique.
- `position_id` on Trade: set to the synthesized `positionID` from `raw_payload`.

## Authorization Strategy

All controller actions scope through `current_user.exchange_accounts` then `account.trades`.
Edit/destroy guard: `trade.manual?` (checks `exchange_reference_id.start_with?("manual_")`).

---

## Tasks

### Task 1 — Add `Trade#manual?` helper and model validations

**Files to touch:**
- `app/models/trade.rb`
- `test/models/trade_test.rb`

**What to implement:**

Add a `manual?` predicate to `Trade`:

```ruby
def manual?
  exchange_reference_id.to_s.start_with?("manual_")
end
```

Add presence validations for `:symbol`, `:side`, `:net_amount`, `:executed_at` if not present.

**Tests to write first (TDD):**

```ruby
test "manual? returns true when exchange_reference_id starts with manual_"
test "manual? returns false for exchange-synced trade"
```

**Acceptance criteria:**
- `trade.manual?` returns `true` iff `exchange_reference_id` starts with `"manual_"`
- Tests pass

---

### Task 2 — Routes: nest ManualTradesController under exchange_accounts

**Files to touch:**
- `config/routes.rb`

**What to implement:**

```ruby
resources :exchange_accounts, only: %i[index new create destroy edit update] do
  member do
    post :sync
    resources :manual_trades, only: %i[new create edit update destroy]
  end
end
```

**Acceptance criteria:**
- `bin/rails routes | grep manual_trade` shows the five routes
- No existing routes broken

---

### Task 3 — ManualTradesController (create, edit, update, destroy)

**Files to touch:**
- `app/controllers/manual_trades_controller.rb` (new)
- `test/controllers/manual_trades_controller_test.rb` (new)

**What to implement:**

```ruby
class ManualTradesController < ApplicationController
  before_action :set_account
  before_action :set_trade, only: %i[edit update destroy]

  def new
    @trade = ManualTrade.new
  end

  def create
    @trade = ManualTrade.new(manual_trade_params)
    @trade.exchange_account = @account
    if @trade.save
      Positions::RebuildForAccountService.call(@account)
      redirect_to exchange_accounts_path, notice: "Trade added and positions rebuilt."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    @trade.assign_from_params(manual_trade_params)
    if @trade.save
      Positions::RebuildForAccountService.call(@account)
      redirect_to exchange_accounts_path, notice: "Trade updated and positions rebuilt."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @trade.trade_record.destroy
    Positions::RebuildForAccountService.call(@account)
    redirect_to exchange_accounts_path, notice: "Trade deleted and positions rebuilt."
  end

  private

  def set_account
    @account = current_user.exchange_accounts.find(params[:exchange_account_id])
  end

  def set_trade
    trade = @account.trades.find(params[:id])
    unless trade.manual?
      redirect_to exchange_accounts_path, alert: "Only manually-entered trades can be edited."
      return
    end
    @trade = ManualTrade.from_trade(trade)
  end

  def manual_trade_params
    params.require(:manual_trade).permit(
      :symbol, :side, :quantity, :price, :executed_at,
      :fee, :position_side, :leverage, :reduce_only, :realized_pnl
    )
  end
end
```

**Tests to write first (TDD):**

```ruby
test "GET new returns 200"
test "POST create with valid params saves trade and rebuilds positions"
test "POST create with invalid params re-renders new with 422"
test "POST create scopes to current user's accounts (404 on another user's account)"
test "DELETE destroy deletes trade and rebuilds positions"
test "DELETE destroy on non-manual trade redirects with alert"
test "PATCH update edits trade and rebuilds positions"
test "PATCH update on non-manual trade redirects with alert"
test "all actions require login"
```

**Acceptance criteria:**
- Valid create: trade persisted, positions rebuilt, redirect with notice
- Invalid create: 422, form re-rendered with errors
- Cross-user protection: 404 when accessing another user's account
- Edit/destroy of non-manual trade: redirect with alert

---

### Task 4 — ManualTrade form object

**Files to touch:**
- `app/models/manual_trade.rb` (new — plain Ruby, not AR model)
- `test/models/manual_trade_test.rb` (new)

**What to implement:**

```ruby
class ManualTrade
  include ActiveModel::Model
  include ActiveModel::Attributes

  attribute :symbol,        :string
  attribute :side,          :string      # "buy" or "sell"
  attribute :quantity,      :decimal
  attribute :price,         :decimal
  attribute :executed_at,   :datetime
  attribute :fee,           :decimal,    default: 0
  attribute :position_side, :string      # "LONG" or "SHORT" (optional)
  attribute :leverage,      :integer
  attribute :reduce_only,   :boolean,    default: false
  attribute :realized_pnl,  :decimal,    default: 0

  attr_accessor :exchange_account, :trade_record

  validates :symbol, presence: true,
            format: { with: /\A[A-Z0-9]+-[A-Z0-9]+\z/,
                      message: "must be in BASE-QUOTE format (e.g. BTC-USDT)" }
  validates :side,      presence: true, inclusion: { in: %w[buy sell] }
  validates :quantity,  presence: true, numericality: { greater_than: 0 }
  validates :price,     presence: true, numericality: { greater_than: 0 }
  validates :executed_at, presence: true

  def self.from_trade(trade)
    raw = trade.raw_payload || {}
    new(
      symbol:       trade.symbol,
      side:         raw["side"]&.downcase,
      quantity:     raw["executedQty"]&.to_d,
      price:        raw["avgPrice"]&.to_d,
      executed_at:  trade.executed_at,
      fee:          trade.fee,
      position_side: raw["positionSide"],
      leverage:     trade.leverage_from_raw,
      reduce_only:  raw["reduceOnly"] == true,
      realized_pnl: raw["profit"]&.to_d || 0
    ).tap { |m| m.trade_record = trade }
  end

  def assign_from_params(attrs)
    assign_attributes(attrs)
  end

  def save
    return false unless valid?
    trade_record ? update_trade_record : create_trade_record
  end

  def persisted? = trade_record&.persisted? || false
  def id         = trade_record&.id

  private

  def create_trade_record
    ts_ms  = (executed_at.to_f * 1000).to_i
    ref_id = "manual_#{ts_ms}_#{SecureRandom.hex(4)}"
    pos_id = "manual_pos_#{ts_ms}_#{SecureRandom.hex(4)}"
    t = Trade.new(
      exchange_account:      exchange_account,
      exchange_reference_id: ref_id,
      symbol:      symbol.upcase,
      side:        side.downcase,
      fee:         fee || 0,
      net_amount:  computed_net_amount,
      executed_at: executed_at,
      position_id: pos_id,
      raw_payload: build_raw_payload(pos_id)
    )
    if t.save
      self.trade_record = t
      true
    else
      t.errors.each { |e| errors.add(e.attribute, e.message) }
      false
    end
  end

  def update_trade_record
    pos_id = trade_record.position_id
    trade_record.assign_attributes(
      symbol:      symbol.upcase,
      side:        side.downcase,
      fee:         fee || 0,
      net_amount:  computed_net_amount,
      executed_at: executed_at,
      raw_payload: build_raw_payload(pos_id)
    )
    if trade_record.save
      true
    else
      trade_record.errors.each { |e| errors.add(e.attribute, e.message) }
      false
    end
  end

  def computed_net_amount
    val = (quantity || 0) * (price || 0)
    side.to_s.downcase == "sell" ? val.abs : -val.abs
  end

  def build_raw_payload(pos_id)
    {
      "side"         => side.upcase,
      "executedQty"  => quantity.to_s,
      "avgPrice"     => price.to_s,
      "positionSide" => position_side.presence&.upcase || (side.downcase == "buy" ? "LONG" : "SHORT"),
      "reduceOnly"   => reduce_only == true,
      "leverage"     => leverage.present? ? "#{leverage}X" : nil,
      "positionID"   => pos_id,
      "profit"       => realized_pnl.to_s
    }.compact
  end
end
```

**Tests to write first (TDD):**

```ruby
test "valid with all required fields"
test "invalid when symbol blank"
test "invalid when symbol not in BASE-QUOTE format"
test "invalid when quantity zero or negative"
test "invalid when price zero or negative"
test "invalid when executed_at blank"
test "net_amount is negative for buy"
test "net_amount is positive for sell"
test "raw_payload contains all required BingX keys"
test "raw_payload leverage formatted as '10X'"
test "raw_payload positionSide inferred from side when position_side blank"
test "raw_payload reduceOnly is boolean"
test "save creates a Trade record with exchange_reference_id starting with manual_"
test "from_trade round-trips symbol, side, quantity, price"
```

**Acceptance criteria:**
- All validations surface field-level errors through `errors`
- `save` creates a `Trade` with `exchange_reference_id =~ /\Amanual_/`
- `raw_payload` passes through all keys that `PositionSummary` reads
- `net_amount` sign is correct for both sides
- `from_trade` reconstructs all editable fields from existing manual trade's `raw_payload`

---

### Task 5 — Views: new/edit form and exchange_accounts index button

**Files to touch:**
- `app/views/manual_trades/new.html.erb` (new)
- `app/views/manual_trades/edit.html.erb` (new)
- `app/views/manual_trades/_form.html.erb` (new partial)
- `app/views/exchange_accounts/index.html.erb` (add "Add trade" button per account row)

**Form fields:**
- Symbol (text, required, placeholder "BTC-USDT")
- Side (select: buy/sell, required)
- Quantity (number, required, > 0)
- Price (number, required, > 0)
- Net amount preview (read-only, computed by Stimulus controller)
- Executed at (datetime-local, required)
- Fee (number, optional, default 0)
- Position side (select: LONG/SHORT/auto-detect, optional)
- Leverage (number, optional, e.g. 10)
- Reduce only (checkbox)
- Realized P&L (number, optional, for closing trades)

Use raw Rails form helpers (`f.number_field`, `f.select`, `f.datetime_local_field`) —
do NOT use `FormFieldComponent` which only supports text/password inputs.

**Acceptance criteria:**
- "Add trade" link visible per account row on the exchange accounts index
- Form renders all fields with labels, error summary on invalid submit
- Cancel link returns to `exchange_accounts_path`
- `datetime-local` input pre-populates correctly on edit

---

### Task 6 — Stimulus controller: `manual-trade-form`

**Files to touch:**
- `app/javascript/controllers/manual_trade_form_controller.js` (new)
- `app/javascript/controllers/index.js` (register)

**What to implement:**

Computes `qty * price` and shows it as a signed preview. Updates on `input` events
on quantity/price and on `change` events on side select. No dependencies.

```js
import { Controller } from "@hotwired/stimulus"
export default class extends Controller {
  static targets = ["quantity", "price", "netAmountPreview"]

  connect() { this.updateNetAmount() }

  updateNetAmount() {
    const qty   = parseFloat(this.quantityTarget?.value) || 0
    const price = parseFloat(this.priceTarget?.value)   || 0
    const side  = this.element.querySelector('select[name$="[side]"]')?.value || "buy"

    if (!this.hasNetAmountPreviewTarget) return

    if (qty <= 0 || price <= 0) {
      this.netAmountPreviewTarget.textContent = "—"
      return
    }

    const notional = qty * price
    const signed   = side === "sell" ? notional : -notional
    const formatted = new Intl.NumberFormat("en-US", {
      style: "currency", currency: "USD",
      minimumFractionDigits: 2, maximumFractionDigits: 8
    }).format(signed)

    this.netAmountPreviewTarget.textContent =
      `${formatted} (${side === "sell" ? "received" : "spent"})`
  }
}
```

**Acceptance criteria:**
- Preview updates immediately on quantity, price, or side change
- Shows "—" when inputs are empty or zero
- Sign is correct: sell = positive, buy = negative

---

### Task 7 — Visual badge + edit/delete controls in the trades index

**Files to touch:**
- `app/views/trades/index.html.erb`
- `app/helpers/trades_helper.rb`

**What to implement:**

In `trades_helper.rb`, add:

```ruby
def position_has_manual_trade?(position_summary)
  position_summary.trades.any?(&:manual?)
end
```

In `trades/index.html.erb`:

1. In the symbol cell (or after it), add an amber badge when the row has manual trades:
   ```erb
   <% if position_has_manual_trade?(pos) %>
     <span class="ml-1.5 inline-flex items-center rounded bg-amber-100 px-1.5 py-0.5 text-xs font-medium text-amber-700">manual</span>
   <% end %>
   ```

2. Add an actions column after the existing columns for edit/delete of manual trades:
   ```erb
   <td class="px-4 py-3 text-right text-sm whitespace-nowrap">
     <% pos.trades.select(&:manual?).each do |t| %>
       <%= link_to "Edit",
           edit_exchange_account_manual_trade_path(t.exchange_account, t),
           class: "mr-2 text-slate-500 hover:text-slate-800 text-xs" %>
       <%= button_to "Delete",
           exchange_account_manual_trade_path(t.exchange_account, t),
           method: :delete,
           data: { turbo_confirm: "Delete this manual trade and rebuild positions?" },
           class: "text-red-500 hover:text-red-700 text-xs bg-transparent border-0 p-0 cursor-pointer" %>
     <% end %>
   </td>
   ```
   Add a matching blank `<th>` in `<thead>`.

**Acceptance criteria:**
- Manual trade rows show amber "manual" badge
- Manual trade rows show Edit/Delete controls
- Exchange-synced rows show no badge and no controls
- Delete triggers browser confirmation dialog

---

## Implementation Order

1. Task 1 — `Trade#manual?` + tests
2. Task 2 — Routes
3. Task 4 — `ManualTrade` form object + tests
4. Task 3 — `ManualTradesController` + tests
5. Task 5 — Views (new/edit form + index button)
6. Task 6 — Stimulus controller
7. Tasks 7 — Badge + edit/delete in trades index

Tasks 5, 6, 7 can be parallelised once Tasks 1–4 are done.

---

## Technical Decisions

**Why a form object (`ManualTrade`) instead of `Trade` directly?**
`Trade` has no first-class `quantity`, `price`, `position_side`, etc. — they live in
`raw_payload`. The form object isolates `raw_payload` synthesis and gives clean
`ActiveModel::Validations` with field-level errors.

**Why synchronous position rebuild?**
`Positions::RebuildForAccountService` runs in milliseconds. Async would require
optimistic UI handling; synchronous keeps it simple for v1.

**Linking manual opens and closes into the same position (v1 limitation)**
Each new manual trade gets its own unique `positionID`. In v1, users entering a
complete open+close pair should enter the open first, note the generated `positionID`
(visible in raw data), and enter it manually on the close. A future iteration could
add a "link to existing position" UI.

---

## Acceptance Criteria (feature-level)

- [ ] "Add trade" link per account on the exchange accounts index
- [ ] Form has required fields: symbol, side, quantity, price, executed_at
- [ ] Form has optional fields: fee, position_side, leverage, reduce_only, realized_pnl
- [ ] Symbol validates to BASE-QUOTE format
- [ ] Quantity and price must be > 0
- [ ] Net amount preview updates live via Stimulus
- [ ] Saved trade has `exchange_reference_id` starting with `"manual_"`
- [ ] `raw_payload` includes: `side`, `executedQty`, `avgPrice`, `positionSide`, `reduceOnly`, `leverage` (if given), `positionID`, `profit`
- [ ] After create/update/destroy: `Positions::RebuildForAccountService.call(account)` runs
- [ ] Edit/delete links visible only for manual-trade rows in trades index
- [ ] Attempting to edit/delete a non-manual trade via URL returns redirect with alert
- [ ] Manual trades show an amber "manual" badge in the trades index
- [ ] Cross-user access returns 404
- [ ] All minitest tests pass

---

## Files Summary

### New files
- `app/models/manual_trade.rb`
- `app/controllers/manual_trades_controller.rb`
- `app/views/manual_trades/new.html.erb`
- `app/views/manual_trades/edit.html.erb`
- `app/views/manual_trades/_form.html.erb`
- `app/javascript/controllers/manual_trade_form_controller.js`
- `test/models/manual_trade_test.rb`
- `test/controllers/manual_trades_controller_test.rb`

### Modified files
- `app/models/trade.rb` — add `manual?`
- `config/routes.rb` — nest `manual_trades`
- `app/views/exchange_accounts/index.html.erb` — "Add trade" button
- `app/views/trades/index.html.erb` — badge + edit/delete controls
- `app/helpers/trades_helper.rb` — `position_has_manual_trade?`
- `app/javascript/controllers/index.js` — register controller
- `test/models/trade_test.rb` — `manual?` tests
