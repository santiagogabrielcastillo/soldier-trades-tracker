# Spot Scenario Calculator Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a collapsible inline scenario calculator below the spot portfolio table that lets the user redistribute cash across positions via sliders (manual) or an optimizer, projecting new ROI live in the browser.

**Architecture:** Pure client-side Stimulus controller (`spot-scenario`) seeded with position + portfolio data as JSON `data-` attributes from Rails. No new routes. All arithmetic (breakeven, ROI, optimizer) runs in JavaScript. The panel is collapsed by default and resets on close (ephemeral).

**Tech Stack:** Rails 7 + Stimulus (Hotwire) + Tailwind CSS + importmap-rails. Tests: Minitest (controller) + Capybara system test.

---

## File Map

| File | Action | Responsibility |
|---|---|---|
| `app/controllers/spot_controller.rb` | Modify | Add `@scenario_positions_json` to `load_index_data` |
| `app/views/spot/_scenario_calculator.html.erb` | Create | Panel HTML shell with all data-* attributes and Stimulus targets |
| `app/views/spot/index.html.erb` | Modify | Render `_scenario_calculator` partial below positions table |
| `app/javascript/controllers/spot_scenario_controller.js` | Create | All calculator logic: toggle, budget sync, sliders, optimizer |
| `test/controllers/spot_controller_test.rb` | Modify | Assert scenario data attributes rendered on portfolio view |
| `test/system/spot_scenario_test.rb` | Create | Capybara flows: toggle open, budget inputs sync, slider updates ROI, optimizer runs |

---

## Task 1: Serialize position data in SpotController

**Files:**
- Modify: `app/controllers/spot_controller.rb` — `load_index_data` method (lines ~225–236)
- Modify: `test/controllers/spot_controller_test.rb`

- [ ] **Step 1: Write the failing test**

Add to `test/controllers/spot_controller_test.rb`:

```ruby
test "portfolio view renders scenario calculator data attributes with positions JSON" do
  sign_in_as(@user)
  account = SpotAccount.find_or_create_default_for(@user)
  account.spot_transactions.destroy_all
  account.spot_transactions.create!(
    token: "BTC", side: "buy", amount: 0.5, price_usd: 72_400,
    total_value_usd: 36_200, executed_at: 1.week.ago,
    row_signature: "btc_scenario_test_1"
  )
  account.update!(cached_prices: { "BTC" => "42100" }, prices_synced_at: Time.current)

  get spot_path
  assert_response :success
  assert_select "[data-spot-scenario-positions-value]"
  assert_select "[data-spot-scenario-cash-balance-value]"
  assert_select "[data-spot-scenario-total-portfolio-value]"
  assert_match(/"token":"BTC"/, response.body)
  assert_match(/"current_price":"42100"/, response.body)
end
```

- [ ] **Step 2: Run test to confirm it fails**

```bash
bin/rails test test/controllers/spot_controller_test.rb -n "test_portfolio_view_renders_scenario_calculator_data_attributes_with_positions_JSON"
```

Expected: FAIL — `data-spot-scenario-positions-value` not found.

- [ ] **Step 3: Add `@scenario_positions_json` to `load_index_data`**

In `app/controllers/spot_controller.rb`, modify `load_index_data` to append after the existing `@cash_pct` line:

```ruby
def load_index_data
  all_positions = Spot::PositionStateService.call(spot_account: @spot_account)
  open_positions = all_positions.select(&:open?)
  @current_prices = @spot_account.prices_as_decimals
  @prices_synced_at = @spot_account.prices_synced_at
  @positions = open_positions.sort_by { |pos| -((@current_prices[pos.token] || 0).to_d * pos.balance) }
  @tokens_for_select = tokens_for_select_for(@spot_account)
  @cash_balance = @spot_account.cash_balance
  @spot_value = open_positions.sum(BigDecimal("0")) { |pos| (@current_prices[pos.token] || 0).to_d * pos.balance }
  @total_portfolio = @spot_value + @cash_balance
  @cash_pct = @total_portfolio.positive? ? (@cash_balance / @total_portfolio * 100).round(2) : nil
  @scenario_positions_json = @positions.map { |pos|
    {
      token: pos.token,
      balance: pos.balance.to_s,
      net_usd_invested: pos.net_usd_invested.to_s,
      breakeven: pos.breakeven.to_s,
      current_price: @current_prices[pos.token]&.to_s
    }
  }.to_json
end
```

- [ ] **Step 4: Run test to confirm it passes**

```bash
bin/rails test test/controllers/spot_controller_test.rb -n "test_portfolio_view_renders_scenario_calculator_data_attributes_with_positions_JSON"
```

Expected: PASS.

- [ ] **Step 5: Run the full controller test suite to check for regressions**

```bash
bin/rails test test/controllers/spot_controller_test.rb
```

Expected: all existing tests pass.

- [ ] **Step 6: Commit**

```bash
git add app/controllers/spot_controller.rb test/controllers/spot_controller_test.rb
git commit -m "feat(spot): serialize scenario positions JSON in load_index_data"
```

---

## Task 2: Create the panel partial and wire it into the index view

> **IMPORTANT:** Invoke the `frontend-design` skill before writing the HTML in this task. The skill provides guidance for production-grade visual quality. The panel uses an indigo accent palette (`#6366f1`) to distinguish it from the slate portfolio table above it.

**Files:**
- Create: `app/views/spot/_scenario_calculator.html.erb`
- Modify: `app/views/spot/index.html.erb`

- [ ] **Step 1: Invoke the `frontend-design` skill**

Use the `frontend-design` skill to guide the visual implementation of the panel partial before writing HTML.

- [ ] **Step 2: Create `app/views/spot/_scenario_calculator.html.erb`**

```erb
<%# Scenario calculator — collapsible panel, all calc logic in spot_scenario_controller.js %>
<div
  data-controller="spot-scenario"
  data-spot-scenario-positions-value="<%= @scenario_positions_json.html_safe %>"
  data-spot-scenario-cash-balance-value="<%= @cash_balance.to_f %>"
  data-spot-scenario-spot-value-value="<%= @spot_value.to_f %>"
  data-spot-scenario-total-portfolio-value="<%= @total_portfolio.to_f %>"
  class="mt-4"
>
  <%# Toggle header %>
  <button
    type="button"
    data-action="click->spot-scenario#toggle"
    class="flex w-full items-center gap-2 border-l-4 border-indigo-500 bg-indigo-50 px-4 py-3 text-left hover:bg-indigo-100 focus:outline-none focus:ring-2 focus:ring-indigo-400"
  >
    <span data-spot-scenario-target="toggleIcon" class="text-indigo-600 font-mono text-sm">▶</span>
    <span class="font-semibold text-indigo-700 text-sm">Scenario calculator</span>
    <span class="ml-1 rounded-full bg-indigo-100 px-2 py-0.5 text-xs text-indigo-500">ephemeral · resets on close</span>
  </button>

  <%# Collapsible content (hidden by default) %>
  <div data-spot-scenario-target="panel" class="hidden border border-t-0 border-indigo-100 bg-indigo-50/30 p-5">

    <%# ── Cash budget section ── %>
    <div class="mb-5 flex flex-wrap items-end gap-5 rounded-lg border border-indigo-100 bg-white p-4">
      <div>
        <p class="text-xs font-semibold uppercase tracking-wide text-indigo-500">Current cash</p>
        <p class="mt-1 text-lg font-bold text-slate-900"><%= format_money(@cash_balance) %></p>
        <p class="text-xs text-slate-400"><%= @cash_pct ? "#{@cash_pct}% of portfolio" : "—" %></p>
      </div>

      <span class="pb-1 text-slate-300 text-xl">→</span>

      <div>
        <label class="text-xs font-semibold uppercase tracking-wide text-indigo-500" for="scenario-cash-pct">
          Target cash %
        </label>
        <div class="mt-1 flex items-center gap-1">
          <input
            id="scenario-cash-pct"
            type="number" min="0" max="100" step="0.1"
            data-spot-scenario-target="targetCashPct"
            data-action="input->spot-scenario#onTargetCashPctInput"
            class="w-20 rounded-md border border-indigo-200 px-2 py-1.5 text-right text-sm text-slate-900 focus:border-indigo-400 focus:outline-none focus:ring-1 focus:ring-indigo-400"
          />
          <span class="text-sm text-slate-500">%</span>
        </div>
      </div>

      <span class="pb-1 text-slate-300">↔</span>

      <div>
        <label class="text-xs font-semibold uppercase tracking-wide text-indigo-500" for="scenario-budget">
          Budget to invest
        </label>
        <div class="mt-1 flex items-center gap-1">
          <span class="text-sm text-slate-500">$</span>
          <input
            id="scenario-budget"
            type="number" min="0" step="0.01"
            data-spot-scenario-target="budgetAmount"
            data-action="input->spot-scenario#onBudgetAmountInput"
            class="w-28 rounded-md border border-indigo-200 px-2 py-1.5 text-sm text-slate-900 focus:border-indigo-400 focus:outline-none focus:ring-1 focus:ring-indigo-400"
          />
        </div>
      </div>

      <p data-spot-scenario-target="afterInvestSummary" class="ml-auto self-end pb-1 text-xs text-slate-400"></p>
    </div>

    <%# ── Mode tab switcher ── %>
    <div class="mb-4 flex w-fit overflow-hidden rounded-lg border border-indigo-200">
      <button
        type="button"
        data-spot-scenario-target="manualTab"
        data-action="click->spot-scenario#switchToManual"
        class="px-5 py-2 text-sm font-semibold"
      >Manual</button>
      <button
        type="button"
        data-spot-scenario-target="optimizeTab"
        data-action="click->spot-scenario#switchToOptimize"
        class="border-l border-indigo-200 px-5 py-2 text-sm font-medium"
      >Optimize</button>
    </div>

    <%# ── Manual mode content ── %>
    <div data-spot-scenario-target="manualContent">
      <div class="overflow-hidden rounded-lg border border-indigo-100 bg-white">
        <table class="w-full border-collapse text-sm">
          <thead>
            <tr class="border-b border-indigo-100 bg-indigo-50/60">
              <th class="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wide text-indigo-500">Token</th>
              <th class="px-4 py-3 text-right text-xs font-semibold uppercase tracking-wide text-indigo-500">Breakeven</th>
              <th class="px-4 py-3 text-right text-xs font-semibold uppercase tracking-wide text-indigo-500">Current ROI</th>
              <th class="px-6 py-3 text-center text-xs font-semibold uppercase tracking-wide text-indigo-500 min-w-[180px]">Inject</th>
              <th class="px-4 py-3 text-right text-xs font-semibold uppercase tracking-wide text-indigo-500">Inject $</th>
              <th class="px-4 py-3 text-right text-xs font-semibold uppercase tracking-wide text-indigo-500">New ROI</th>
            </tr>
          </thead>
          <tbody data-spot-scenario-target="sliderBody">
            <%# Rows rendered dynamically by spot_scenario_controller.js %>
          </tbody>
        </table>

        <%# Budget progress bar %>
        <div class="flex items-center gap-3 border-t border-indigo-100 bg-indigo-50/60 px-4 py-2.5">
          <span class="text-xs font-semibold text-indigo-600" data-spot-scenario-target="budgetAllocated">Allocated: $0</span>
          <div class="flex-1 h-1.5 overflow-hidden rounded-full bg-indigo-100">
            <div data-spot-scenario-target="budgetBar" class="h-full rounded-full bg-indigo-500 transition-all" style="width:0%"></div>
          </div>
          <span class="text-xs text-slate-400" data-spot-scenario-target="budgetRemaining">$0 remaining</span>
        </div>
      </div>
    </div>

    <%# ── Optimize mode content (hidden initially) ── %>
    <div data-spot-scenario-target="optimizeContent" class="hidden">

      <%# Config row %>
      <div class="mb-4 flex flex-wrap items-end gap-6 rounded-lg border border-indigo-100 bg-white p-4">

        <%# Optimizer mode toggle %>
        <div>
          <p class="mb-2 text-xs font-semibold uppercase tracking-wide text-indigo-500">Optimizer mode</p>
          <div class="flex overflow-hidden rounded-md border border-indigo-200 text-sm">
            <button
              type="button"
              data-spot-scenario-target="optimizerModeFixed"
              data-action="click->spot-scenario#setModeFixed"
              class="px-4 py-1.5 font-semibold"
            >Fixed target ROI</button>
            <button
              type="button"
              data-spot-scenario-target="optimizerModeFloor"
              data-action="click->spot-scenario#setModeFloor"
              class="border-l border-indigo-200 px-4 py-1.5"
            >Best achievable floor</button>
          </div>
        </div>

        <%# Target ROI input (fixed mode only) %>
        <div data-spot-scenario-target="targetRoiWrapper">
          <label class="mb-2 block text-xs font-semibold uppercase tracking-wide text-indigo-500">Target ROI</label>
          <div class="flex items-center gap-1">
            <input
              type="number" step="0.1"
              value="-30"
              data-spot-scenario-target="targetRoi"
              class="w-20 rounded-md border border-indigo-200 px-2 py-1.5 text-right text-sm text-slate-900 focus:border-indigo-400 focus:outline-none focus:ring-1 focus:ring-indigo-400"
            />
            <span class="text-sm text-slate-500">%</span>
          </div>
        </div>

        <%# Position checkboxes (rendered dynamically) %>
        <div>
          <p class="mb-2 text-xs font-semibold uppercase tracking-wide text-indigo-500">Apply to positions</p>
          <div data-spot-scenario-target="checkboxContainer" class="flex flex-wrap gap-3"></div>
        </div>

        <%# Optimize button %>
        <div class="ml-auto">
          <button
            type="button"
            data-spot-scenario-target="optimizeBtn"
            data-action="click->spot-scenario#runOptimizer"
            class="rounded-md bg-indigo-600 px-5 py-2 text-sm font-semibold text-white hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-indigo-500 disabled:cursor-not-allowed disabled:opacity-50"
          >Optimize ✦</button>
        </div>
      </div>

      <%# Results area (populated by controller) %>
      <div data-spot-scenario-target="optimizeResults"></div>
    </div>

  </div>
</div>
```

- [ ] **Step 3: Render the partial from `app/views/spot/index.html.erb`**

Find the closing `<% end %>` of the `@positions.any?` block (after the positions table and the exchange accounts note, around line 122–125). Add the partial render immediately after the `<% end %>` that closes the `if @positions.any?` block, but still inside the `<% if @view == "portfolio" %>` section:

```erb
  <% if @positions.any? %>
    <%# ... existing positions table ... %>
  <% else %>
    <%= render EmptyStateComponent.new(message: "No spot positions yet. Upload a transaction history CSV above to get started.") %>
  <% end %>

  <%= render "scenario_calculator" %>
```

- [ ] **Step 4: Boot the dev server and verify the panel toggle button renders on the portfolio page**

```bash
./bin/dev
```

Open `http://localhost:5000/spot` — confirm "▶ Scenario calculator" button appears below the positions table (or empty state). Clicking it should do nothing yet (controller not wired).

- [ ] **Step 5: Commit**

```bash
git add app/views/spot/_scenario_calculator.html.erb app/views/spot/index.html.erb
git commit -m "feat(spot): add scenario calculator partial shell"
```

---

## Task 3: Stimulus controller — scaffold, toggle, and budget inputs

**Files:**
- Create: `app/javascript/controllers/spot_scenario_controller.js`

- [ ] **Step 1: Create the controller file**

```javascript
// app/javascript/controllers/spot_scenario_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    positions: Array,      // [{token, balance, net_usd_invested, breakeven, current_price}]
    cashBalance: Number,
    spotValue: Number,
    totalPortfolio: Number,
  }

  static targets = [
    "panel", "toggleIcon",
    "targetCashPct", "budgetAmount", "afterInvestSummary",
    "manualTab", "optimizeTab", "manualContent", "optimizeContent",
    "sliderBody", "budgetBar", "budgetAllocated", "budgetRemaining",
    "optimizerModeFixed", "optimizerModeFloor", "targetRoiWrapper",
    "targetRoi", "checkboxContainer", "optimizeBtn", "optimizeResults",
  ]

  connect() {
    this._open = false
    this._activeTab = "manual"
    this._optimizerMode = "fixed"
    this._sliderValues = {} // token -> allocated amount
  }

  // ── Panel toggle ──────────────────────────────────────────────

  toggle() {
    this._open = !this._open
    this.panelTarget.classList.toggle("hidden", !this._open)
    this.toggleIconTarget.textContent = this._open ? "▼" : "▶"
    if (this._open) this._initPanel()
  }

  _initPanel() {
    const currentPct = this.totalPortfolioValue > 0
      ? (this.cashBalanceValue / this.totalPortfolioValue * 100)
      : 0
    this.targetCashPctTarget.value = currentPct.toFixed(1)
    this.budgetAmountTarget.value = "0.00"
    this._updateAfterInvestSummary(0)
    this._activateTab("manual")
    this._initOptimizerMode("fixed")
    this._resetSliders()
    this._renderCheckboxes()
  }

  // ── Budget inputs ─────────────────────────────────────────────

  onTargetCashPctInput() {
    const pct = parseFloat(this.targetCashPctTarget.value) || 0
    const budget = Math.max(0, this.cashBalanceValue - (pct / 100) * this.totalPortfolioValue)
    this.budgetAmountTarget.value = budget.toFixed(2)
    this._updateAfterInvestSummary(budget)
    this._resetSliders()
  }

  onBudgetAmountInput() {
    const budget = Math.max(0, parseFloat(this.budgetAmountTarget.value) || 0)
    const newCash = this.cashBalanceValue - budget
    const newPct = this.totalPortfolioValue > 0 ? (newCash / this.totalPortfolioValue * 100) : 0
    this.targetCashPctTarget.value = Math.max(0, newPct).toFixed(1)
    this._updateAfterInvestSummary(budget)
    this._resetSliders()
  }

  _updateAfterInvestSummary(budget) {
    const newCash = this.cashBalanceValue - budget
    const newPct = this.totalPortfolioValue > 0 ? (newCash / this.totalPortfolioValue * 100) : 0
    this.afterInvestSummaryTarget.textContent =
      `After invest: cash = ${this._formatMoney(Math.max(0, newCash))} (${Math.max(0, newPct).toFixed(1)}%)`
  }

  get budget() {
    return Math.max(0, parseFloat(this.budgetAmountTarget.value) || 0)
  }

  // ── Tab switching ─────────────────────────────────────────────

  switchToManual() { this._activateTab("manual") }
  switchToOptimize() { this._activateTab("optimize") }

  _activateTab(tab) {
    this._activeTab = tab
    const isManual = tab === "manual"
    this.manualContentTarget.classList.toggle("hidden", !isManual)
    this.optimizeContentTarget.classList.toggle("hidden", isManual)
    this.manualTabTarget.classList.toggle("bg-indigo-600", isManual)
    this.manualTabTarget.classList.toggle("text-white", isManual)
    this.manualTabTarget.classList.toggle("text-indigo-600", !isManual)
    this.optimizeTabTarget.classList.toggle("bg-indigo-600", !isManual)
    this.optimizeTabTarget.classList.toggle("text-white", !isManual)
    this.optimizeTabTarget.classList.toggle("text-indigo-600", isManual)
    if (isManual) this._renderSliderRows()
  }

  // ── Optimizer mode toggle ─────────────────────────────────────

  setModeFixed() { this._initOptimizerMode("fixed") }
  setModeFloor() { this._initOptimizerMode("floor") }

  _initOptimizerMode(mode) {
    this._optimizerMode = mode
    const isFixed = mode === "fixed"
    this.targetRoiWrapperTarget.classList.toggle("hidden", !isFixed)
    this.optimizerModeFixedTarget.classList.toggle("bg-indigo-600", isFixed)
    this.optimizerModeFixedTarget.classList.toggle("text-white", isFixed)
    this.optimizerModeFixedTarget.classList.toggle("text-indigo-600", !isFixed)
    this.optimizerModeFloorTarget.classList.toggle("bg-indigo-600", !isFixed)
    this.optimizerModeFloorTarget.classList.toggle("text-white", !isFixed)
    this.optimizerModeFloorTarget.classList.toggle("text-indigo-600", isFixed)
    this.optimizeResultsTarget.innerHTML = "" // clear stale results
  }

  // ── Helpers ───────────────────────────────────────────────────

  _formatMoney(value) {
    if (value == null || isNaN(value)) return "—"
    return "$" + parseFloat(value).toLocaleString("en-US", {
      minimumFractionDigits: 2, maximumFractionDigits: 2,
    })
  }

  _formatRoi(roi, isRiskFree) {
    if (isRiskFree) return "Risk free"
    if (roi == null || !isFinite(roi)) return "—"
    return (roi >= 0 ? "+" : "") + roi.toFixed(2) + "%"
  }

  _roiColorClass(roi, isRiskFree) {
    if (isRiskFree) return "text-emerald-600"
    if (roi == null || !isFinite(roi)) return "text-slate-400"
    if (roi >= 0) return "text-emerald-600"
    return "text-red-600"
  }

  _newRoiColorClass(currentRoi, newRoi, isRiskFree) {
    if (isRiskFree) return "text-emerald-600"
    if (newRoi == null || !isFinite(newRoi)) return "text-slate-400"
    if (newRoi >= 0) return "text-emerald-600"
    if (newRoi > (currentRoi || newRoi)) return "text-amber-600" // improved but still negative
    return "text-red-600"
  }

  _escapeAttr(s) {
    return String(s).replace(/&/g, "&amp;").replace(/"/g, "&quot;")
  }

  _calcCurrentRoi(pos) {
    const breakeven = parseFloat(pos.breakeven)
    const currentPrice = parseFloat(pos.current_price)
    if (!breakeven || !currentPrice) return null
    return (currentPrice - breakeven) / breakeven * 100
  }

  _isRiskFree(pos) {
    return parseFloat(pos.net_usd_invested) < 0
  }

  _calcProjectedRoi(pos, injection) {
    const balance = parseFloat(pos.balance)
    const netUsd = parseFloat(pos.net_usd_invested)
    const currentPrice = parseFloat(pos.current_price)
    if (!currentPrice || !balance) return null
    const newBalance = balance + injection / currentPrice
    const newBreakeven = (netUsd + injection) / newBalance
    if (newBreakeven <= 0) return Infinity
    return (currentPrice - newBreakeven) / newBreakeven * 100
  }

  // Injection in $ needed to bring pos to targetRoiPct. Returns 0 if already there/past.
  _calcInjectionNeeded(pos, targetRoiPct) {
    const balance = parseFloat(pos.balance)
    const netUsd = parseFloat(pos.net_usd_invested)
    const currentPrice = parseFloat(pos.current_price)
    if (!currentPrice) return 0
    const targetBreakeven = currentPrice / (1 + targetRoiPct / 100)
    const denominator = 1 - targetBreakeven / currentPrice
    if (Math.abs(denominator) < 1e-10) return 0
    return Math.max(0, (targetBreakeven * balance - netUsd) / denominator)
  }

  _resetSliders() {
    this.positionsValue.forEach(p => { this._sliderValues[p.token] = 0 })
    if (this._activeTab === "manual") this._renderSliderRows()
    this._updateBudgetBar()
  }

  _renderCheckboxes() { /* implemented in Task 5 */ }
  _renderSliderRows() { /* implemented in Task 4 */ }
  _updateBudgetBar() { /* implemented in Task 4 */ }
  runOptimizer() { /* implemented in Tasks 5–6 */ }
}
```

- [ ] **Step 2: Verify the toggle works in the browser**

```bash
./bin/dev
```

Open `http://localhost:5000/spot`. Click "▶ Scenario calculator" — panel should expand (▼), click again — should collapse (▶). Changing the target cash % input should update the budget $ field and vice versa. The "After invest:" summary should update.

- [ ] **Step 3: Commit**

```bash
git add app/javascript/controllers/spot_scenario_controller.js
git commit -m "feat(spot-scenario): scaffold controller — toggle, budget inputs, tab/mode switching"
```

---

## Task 4: Manual mode — slider rows, live ROI, budget bar

**Files:**
- Modify: `app/javascript/controllers/spot_scenario_controller.js`

Replace the three stub methods (`_renderSliderRows`, `_updateBudgetBar`, and the stub `_renderCheckboxes`) with full implementations.

- [ ] **Step 1: Replace `_renderSliderRows` stub**

```javascript
_renderSliderRows() {
  const budget = this.budget
  const positions = this.positionsValue

  this.sliderBodyTarget.innerHTML = positions.map(pos => {
    const currentRoi = this._calcCurrentRoi(pos)
    const isRiskFree = this._isRiskFree(pos)
    const hasPrice = !!pos.current_price
    const disabled = !hasPrice || isRiskFree || budget <= 0
    const injection = this._sliderValues[pos.token] || 0
    const newRoi = disabled ? currentRoi : this._calcProjectedRoi(pos, injection)

    const currentRoiStr = this._formatRoi(currentRoi, isRiskFree)
    const currentRoiClass = this._roiColorClass(currentRoi, isRiskFree)
    const newRoiStr = this._formatRoi(newRoi, isRiskFree)
    const newRoiClass = this._newRoiColorClass(currentRoi, newRoi, isRiskFree)
    const injectStr = injection > 0 ? this._formatMoney(injection) : "$0"
    const injectClass = injection > 0 ? "font-semibold text-indigo-600" : "text-slate-400"
    const tooltip = !hasPrice ? "Sync prices first" : (isRiskFree ? "Risk-free position" : "")
    const rowClass = disabled ? "opacity-50" : ""

    return `
      <tr class="border-b border-slate-100 ${rowClass}" data-token="${this._escapeAttr(pos.token)}">
        <td class="whitespace-nowrap px-4 py-3 font-semibold text-slate-900">${this._escapeAttr(pos.token)}</td>
        <td class="whitespace-nowrap px-4 py-3 text-right text-slate-600">${pos.breakeven ? this._formatMoney(parseFloat(pos.breakeven)) : "—"}</td>
        <td class="whitespace-nowrap px-4 py-3 text-right font-semibold ${currentRoiClass}">${currentRoiStr}</td>
        <td class="px-6 py-3">
          <input
            type="range" min="0" max="${budget}" step="1" value="${injection}"
            ${disabled ? 'disabled title="' + this._escapeAttr(tooltip) + '"' : ''}
            data-action="input->spot-scenario#onSliderInput"
            data-token="${this._escapeAttr(pos.token)}"
            class="w-full disabled:cursor-not-allowed"
            style="accent-color:#6366f1"
          />
        </td>
        <td class="whitespace-nowrap px-4 py-3 text-right text-sm ${injectClass}"
            data-inject-amount="${this._escapeAttr(pos.token)}">${injectStr}</td>
        <td class="whitespace-nowrap px-4 py-3 text-right font-semibold ${newRoiClass}"
            data-new-roi="${this._escapeAttr(pos.token)}">${newRoiStr}</td>
      </tr>
    `
  }).join("")

  this._updateBudgetBar()
}
```

- [ ] **Step 2: Add `onSliderInput` action**

```javascript
onSliderInput(event) {
  const token = event.target.dataset.token
  const requested = parseFloat(event.target.value) || 0
  const budget = this.budget

  // Clamp: this slider can only use what's left after other sliders
  const otherSum = Object.entries(this._sliderValues)
    .filter(([t]) => t !== token)
    .reduce((sum, [, v]) => sum + v, 0)
  const maxForThis = Math.max(0, budget - otherSum)
  const clamped = Math.min(requested, maxForThis)
  event.target.value = clamped
  this._sliderValues[token] = clamped

  // Update inject $ cell
  const injectCell = this.sliderBodyTarget.querySelector(`[data-inject-amount="${token}"]`)
  if (injectCell) {
    injectCell.textContent = clamped > 0 ? this._formatMoney(clamped) : "$0"
    injectCell.className = `whitespace-nowrap px-4 py-3 text-right text-sm ${clamped > 0 ? "font-semibold text-indigo-600" : "text-slate-400"}`
  }

  // Update new ROI cell
  const pos = this.positionsValue.find(p => p.token === token)
  if (pos) {
    const currentRoi = this._calcCurrentRoi(pos)
    const isRiskFree = this._isRiskFree(pos)
    const newRoi = this._calcProjectedRoi(pos, clamped)
    const roiCell = this.sliderBodyTarget.querySelector(`[data-new-roi="${token}"]`)
    if (roiCell) {
      roiCell.textContent = this._formatRoi(newRoi, isRiskFree)
      roiCell.className = `whitespace-nowrap px-4 py-3 text-right font-semibold ${this._newRoiColorClass(currentRoi, newRoi, isRiskFree)}`
    }
  }

  this._updateBudgetBar()
}
```

- [ ] **Step 3: Replace `_updateBudgetBar` stub**

```javascript
_updateBudgetBar() {
  const budget = this.budget
  const allocated = Object.values(this._sliderValues).reduce((s, v) => s + v, 0)
  const remaining = Math.max(0, budget - allocated)
  const pct = budget > 0 ? Math.min(100, (allocated / budget) * 100) : 0

  this.budgetBarTarget.style.width = pct + "%"
  this.budgetAllocatedTarget.textContent = `Allocated: ${this._formatMoney(allocated)}`
  this.budgetRemainingTarget.textContent = `${this._formatMoney(remaining)} remaining`

  // Also disable Optimize button when no budget
  if (this.hasOptimizeBtnTarget) {
    this.optimizeBtnTarget.disabled = budget <= 0
  }
}
```

- [ ] **Step 4: Also update `_activateTab` to call `_renderSliderRows` on switch to manual**

This is already in Task 3's `_activateTab` implementation — `if (isManual) this._renderSliderRows()`. Confirm the line is present.

- [ ] **Step 5: Test in the browser**

```bash
./bin/dev
```

Open `http://localhost:5000/spot`. Ensure prices are synced first (click "Sync prices"). Open the calculator panel. Set Target cash % to something lower than current (e.g., 60%). Confirm budget $ updates. Drag a slider — the "Inject $" and "New ROI" cells should update live. Dragging two sliders should not allow the total to exceed the budget.

- [ ] **Step 6: Commit**

```bash
git add app/javascript/controllers/spot_scenario_controller.js
git commit -m "feat(spot-scenario): manual mode — slider rows, live ROI, budget bar"
```

---

## Task 5: Optimize mode — checkboxes, fixed target algorithm, results table

**Files:**
- Modify: `app/javascript/controllers/spot_scenario_controller.js`

- [ ] **Step 1: Replace `_renderCheckboxes` stub**

```javascript
_renderCheckboxes() {
  const eligible = this.positionsValue.filter(p => p.current_price && !this._isRiskFree(p))
  this.checkboxContainerTarget.innerHTML = eligible.map(pos => `
    <label class="flex cursor-pointer items-center gap-1.5 rounded-md border border-indigo-100 bg-indigo-50 px-3 py-1.5 text-sm hover:bg-indigo-100">
      <input type="checkbox" checked
             data-token="${this._escapeAttr(pos.token)}"
             class="rounded accent-indigo-600"
             style="accent-color:#6366f1" />
      <span class="font-medium text-slate-800">${this._escapeAttr(pos.token)}</span>
    </label>
  `).join("")
}
```

- [ ] **Step 2: Implement `runOptimizer`**

```javascript
runOptimizer() {
  const budget = this.budget
  if (budget <= 0) return

  const selectedTokens = new Set(
    [...this.checkboxContainerTarget.querySelectorAll("input[type=checkbox]:checked")]
      .map(cb => cb.dataset.token)
  )
  const allPositions = this.positionsValue.filter(p => p.current_price && !this._isRiskFree(p))
  const selected = allPositions.filter(p => selectedTokens.has(p.token))
  const unselected = allPositions.filter(p => !selectedTokens.has(p.token))

  let results
  if (this._optimizerMode === "fixed") {
    results = this._runFixedTargetOptimizer(selected, budget)
  } else {
    results = this._runBestFloorOptimizer(selected, budget)
  }

  // Merge unselected positions as $0/no-badge rows
  const unselectedResults = unselected.map(pos => ({
    pos,
    injection: 0,
    newRoi: this._calcCurrentRoi(pos),
    status: null,
    selected: false,
  }))

  this._renderOptimizeResults([...results, ...unselectedResults], budget)
}
```

- [ ] **Step 3: Implement `_runFixedTargetOptimizer`**

```javascript
_runFixedTargetOptimizer(positions, budget) {
  const targetRoi = parseFloat(this.targetRoiTarget.value) || -30

  // Compute needed injection for each; skip positions already past target
  const needs = positions.map(pos => {
    const currentRoi = this._calcCurrentRoi(pos)
    if (currentRoi !== null && currentRoi >= targetRoi) {
      return { pos, needed: 0, alreadyPast: true }
    }
    return { pos, needed: this._calcInjectionNeeded(pos, targetRoi), alreadyPast: false }
  })

  // Prioritize deepest (most needed) first
  needs.sort((a, b) => b.needed - a.needed)

  let remaining = budget
  return needs.map(({ pos, needed, alreadyPast }) => {
    if (alreadyPast) {
      return { pos, injection: 0, newRoi: this._calcCurrentRoi(pos), status: "past", selected: true }
    }
    const injection = Math.min(needed, remaining)
    remaining = Math.max(0, remaining - injection)
    const newRoi = this._calcProjectedRoi(pos, injection)
    const metTarget = Math.abs(injection - needed) < 0.01
    const status = metTarget ? "met" : "exhausted"
    return { pos, injection, newRoi, status, selected: true }
  })
}
```

- [ ] **Step 4: Implement `_renderOptimizeResults`**

```javascript
_renderOptimizeResults(results, budget) {
  const totalInjected = results.reduce((s, r) => s + r.injection, 0)
  const metCount = results.filter(r => r.status === "met" || r.status === "equalized").length
  const selectedCount = results.filter(r => r.selected).length

  const badgeHtml = (status) => {
    if (!status) return ""
    const map = {
      met:       ["bg-amber-100 text-amber-700",   "Target met"],
      past:      ["bg-emerald-100 text-emerald-700","Already past target"],
      exhausted: ["bg-orange-100 text-orange-700",  "Budget exhausted"],
      equalized: ["bg-indigo-100 text-indigo-700",  "Equalized"],
    }
    const [cls, label] = map[status] || ["bg-slate-100 text-slate-500", status]
    return `<span class="rounded-full px-2 py-0.5 text-xs font-semibold ${cls}">${label}</span>`
  }

  const rows = results.map(({ pos, injection, newRoi, status, selected }) => {
    const currentRoi = this._calcCurrentRoi(pos)
    const isRiskFree = this._isRiskFree(pos)
    const rowClass = selected ? "" : "opacity-40"
    const injectStr = injection > 0 ? this._formatMoney(injection) : "$0"
    const injectClass = injection > 0 ? "font-semibold text-indigo-600" : "text-slate-400"
    const currentPrice = parseFloat(pos.current_price)
    const newBalance = parseFloat(pos.balance) + injection / currentPrice
    const newBreakeven = (parseFloat(pos.net_usd_invested) + injection) / newBalance
    const newBreakevenStr = injection > 0 ? this._formatMoney(newBreakeven) : "—"
    const newRoiStr = this._formatRoi(newRoi, isRiskFree)
    const newRoiClass = this._newRoiColorClass(currentRoi, newRoi, isRiskFree)

    return `
      <tr class="border-b border-slate-100 ${rowClass}">
        <td class="whitespace-nowrap px-4 py-3 font-semibold text-slate-900">${this._escapeAttr(pos.token)}</td>
        <td class="whitespace-nowrap px-4 py-3 text-right font-semibold ${this._roiColorClass(currentRoi, isRiskFree)}">${this._formatRoi(currentRoi, isRiskFree)}</td>
        <td class="whitespace-nowrap px-4 py-3 text-right ${injectClass}">${injectStr}</td>
        <td class="whitespace-nowrap px-4 py-3 text-right text-slate-600">${newBreakevenStr}</td>
        <td class="whitespace-nowrap px-4 py-3 text-right font-semibold ${newRoiClass}">${newRoiStr}</td>
        <td class="whitespace-nowrap px-4 py-3 text-right">${badgeHtml(status)}</td>
      </tr>
    `
  }).join("")

  this.optimizeResultsTarget.innerHTML = `
    <div class="overflow-hidden rounded-lg border border-indigo-100 bg-white">
      <div class="border-b border-indigo-100 bg-indigo-50/60 px-4 py-2 text-xs font-semibold text-indigo-600">
        Result — ${this._optimizerMode === "fixed"
          ? `Fixed target ${this.targetRoiTarget.value}%`
          : "Best achievable floor"} · Budget ${this._formatMoney(budget)} · ${selectedCount} position${selectedCount !== 1 ? "s" : ""} selected
      </div>
      <table class="w-full border-collapse text-sm">
        <thead>
          <tr class="border-b border-indigo-100 bg-indigo-50/30">
            <th class="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wide text-indigo-500">Token</th>
            <th class="px-4 py-3 text-right text-xs font-semibold uppercase tracking-wide text-indigo-500">Current ROI</th>
            <th class="px-4 py-3 text-right text-xs font-semibold uppercase tracking-wide text-indigo-500">Inject $</th>
            <th class="px-4 py-3 text-right text-xs font-semibold uppercase tracking-wide text-indigo-500">New breakeven</th>
            <th class="px-4 py-3 text-right text-xs font-semibold uppercase tracking-wide text-indigo-500">New ROI</th>
            <th class="px-4 py-3 text-right text-xs font-semibold uppercase tracking-wide text-indigo-500">Status</th>
          </tr>
        </thead>
        <tbody>${rows}</tbody>
      </table>
      <div class="flex items-center gap-3 border-t border-indigo-100 bg-indigo-50/60 px-4 py-2.5 text-xs">
        <span class="font-semibold text-indigo-600">Total injected: ${this._formatMoney(totalInjected)}</span>
        <span class="text-slate-400">·</span>
        <span class="text-slate-500">${metCount} of ${selectedCount} position${selectedCount !== 1 ? "s" : ""} reached target</span>
      </div>
    </div>
  `
}
```

- [ ] **Step 5: Test fixed target optimizer in the browser**

Open `http://localhost:5000/spot`. Open the calculator, set a budget, switch to Optimize tab. Target ROI defaults to −30%. Check a few positions. Click "Optimize ✦". Confirm results table renders with correct injection amounts, new ROI values, and status badges.

- [ ] **Step 6: Commit**

```bash
git add app/javascript/controllers/spot_scenario_controller.js
git commit -m "feat(spot-scenario): optimize mode — checkboxes, fixed target algorithm, results table"
```

---

## Task 6: Optimize mode — best achievable floor algorithm

**Files:**
- Modify: `app/javascript/controllers/spot_scenario_controller.js`

- [ ] **Step 1: Implement `_runBestFloorOptimizer`**

```javascript
_runBestFloorOptimizer(positions, budget) {
  if (positions.length === 0) return []

  // Find the worst current ROI as lower bound
  const rois = positions.map(p => this._calcCurrentRoi(p)).filter(r => r !== null)
  let low = Math.min(...rois, -99)
  let high = Math.max(...rois.map(r => Math.min(r, 0)), -0.01) // floor ≤ 0

  // Binary search for highest floor r* where total injection ≤ budget
  for (let i = 0; i < 60; i++) {
    const mid = (low + high) / 2
    const totalNeeded = positions.reduce((sum, pos) => {
      const currentRoi = this._calcCurrentRoi(pos)
      if (currentRoi !== null && currentRoi >= mid) return sum // already past this floor
      return sum + this._calcInjectionNeeded(pos, mid)
    }, 0)

    if (totalNeeded <= budget) {
      low = mid // achievable, try a better floor
    } else {
      high = mid // too expensive, lower the floor
    }

    if (high - low < 0.01) break // converged (~within $1 for typical position sizes)
  }

  const floorRoi = low
  // Now allocate exactly, respecting budget
  let remaining = budget
  return positions.map(pos => {
    const currentRoi = this._calcCurrentRoi(pos)
    if (currentRoi !== null && currentRoi >= floorRoi) {
      return { pos, injection: 0, newRoi: currentRoi, status: "past", selected: true }
    }
    const needed = this._calcInjectionNeeded(pos, floorRoi)
    const injection = Math.min(needed, remaining)
    remaining = Math.max(0, remaining - injection)
    const newRoi = this._calcProjectedRoi(pos, injection)
    return { pos, injection, newRoi, status: "equalized", selected: true }
  })
}
```

- [ ] **Step 2: Test best floor mode in the browser**

Switch optimizer mode toggle to "Best achievable floor". Click "Optimize ✦". All selected positions should show approximately the same "New ROI" value, and all should show the "Equalized" indigo badge. The total injected should be close to (but not exceed) the budget.

- [ ] **Step 3: Commit**

```bash
git add app/javascript/controllers/spot_scenario_controller.js
git commit -m "feat(spot-scenario): optimize mode — best achievable floor via binary search"
```

---

## Task 7: System test

**Files:**
- Create: `test/system/spot_scenario_test.rb`

- [ ] **Step 1: Write the system test**

```ruby
# test/system/spot_scenario_test.rb
require "application_system_test_case"

class SpotScenarioTest < ApplicationSystemTestCase
  setup do
    @user = users(:one)
    @user.update!(password: "password", password_confirmation: "password")
    @account = SpotAccount.find_or_create_default_for(@user)
    @account.spot_transactions.destroy_all
    @account.spot_transactions.create!(
      token: "BTC", side: "buy", amount: 0.5, price_usd: 70_000,
      total_value_usd: 35_000, executed_at: 2.weeks.ago,
      row_signature: "btc_sys_test_1"
    )
    @account.spot_transactions.create!(
      token: "ETH", side: "buy", amount: 10, price_usd: 3_000,
      total_value_usd: 30_000, executed_at: 2.weeks.ago,
      row_signature: "eth_sys_test_1"
    )
    @account.spot_transactions.create!(
      token: "USDT", side: "deposit", amount: 20_000, price_usd: 1,
      total_value_usd: 20_000, executed_at: 1.week.ago,
      row_signature: "cash_sys_test_1"
    )
    @account.update!(
      cached_prices: { "BTC" => "42000", "ETH" => "1800" },
      prices_synced_at: Time.current
    )
    sign_in_as_system(@user)
  end

  test "scenario panel is collapsed by default and expands on click" do
    visit spot_path
    assert_text "Scenario calculator"
    assert_no_css "[data-spot-scenario-target='panel']:not(.hidden)"
    find("button", text: /Scenario calculator/).click
    assert_css "[data-spot-scenario-target='panel']:not(.hidden)"
  end

  test "budget inputs sync bidirectionally" do
    visit spot_path
    find("button", text: /Scenario calculator/).click

    # Change target cash % → budget updates
    pct_input = find("[data-spot-scenario-target='targetCashPct']")
    budget_input = find("[data-spot-scenario-target='budgetAmount']")

    current_pct = pct_input.value.to_f
    new_pct = [current_pct - 10, 0].max
    pct_input.fill_in with: new_pct.to_s
    pct_input.send_keys :tab

    budget_val = budget_input.value.to_f
    assert budget_val > 0, "budget should be positive after reducing target cash %"

    # Now edit budget directly → pct updates
    pct_after = pct_input.value.to_f
    budget_input.fill_in with: "0"
    budget_input.send_keys :tab
    assert_in_delta current_pct, pct_input.value.to_f, 1.0
  end

  test "slider updates inject amount and new ROI live" do
    visit spot_path
    find("button", text: /Scenario calculator/).click

    pct_input = find("[data-spot-scenario-target='targetCashPct']")
    current_pct = pct_input.value.to_f
    pct_input.fill_in with: [(current_pct - 15), 0].max.to_s
    pct_input.send_keys :tab

    # Find the BTC slider and drag it
    btc_slider = find("input[type='range'][data-token='BTC']")
    max_val = btc_slider["max"].to_f
    # Set slider to 50% of max via JS
    page.execute_script(
      "arguments[0].value = #{max_val * 0.5}; arguments[0].dispatchEvent(new Event('input'));",
      btc_slider.native
    )

    # Inject $ cell should show a non-zero value
    inject_cell = find("[data-inject-amount='BTC']")
    assert inject_cell.text.start_with?("$"), "BTC inject $ cell should show a dollar amount"
    refute_equal "$0", inject_cell.text, "BTC inject $ should be > $0 after sliding"
  end

  test "optimizer fixed target renders results table" do
    visit spot_path
    find("button", text: /Scenario calculator/).click

    pct_input = find("[data-spot-scenario-target='targetCashPct']")
    pct_input.fill_in with: [(pct_input.value.to_f - 20), 0].max.to_s
    pct_input.send_keys :tab

    find("[data-spot-scenario-target='optimizeTab']").click
    find("[data-spot-scenario-target='targetRoi']").fill_in with: "-30"
    find("[data-spot-scenario-target='optimizeBtn']").click

    assert_text "Result"
    assert_text "Fixed target"
    assert_text "BTC"
    assert_text "ETH"
  end

  test "optimizer best floor renders equalized badges" do
    visit spot_path
    find("button", text: /Scenario calculator/).click

    pct_input = find("[data-spot-scenario-target='targetCashPct']")
    pct_input.fill_in with: [(pct_input.value.to_f - 20), 0].max.to_s
    pct_input.send_keys :tab

    find("[data-spot-scenario-target='optimizeTab']").click
    find("[data-spot-scenario-target='optimizerModeFloor']").click
    find("[data-spot-scenario-target='optimizeBtn']").click

    assert_text "Best achievable floor"
    assert_text "Equalized"
  end

  private

  def sign_in_as_system(user)
    visit login_path
    fill_in "Email", with: user.email
    fill_in "Password", with: "password"
    click_button "Sign in"
  end
end
```

- [ ] **Step 2: Check how the existing system tests sign in (adjust `sign_in_as_system` if needed)**

```bash
ls test/system/
```

If a `sign_in_as` helper exists in `test/application_system_test_case.rb` or `test/test_helper.rb`, use it instead of the inline `sign_in_as_system` method above.

- [ ] **Step 3: Run the system tests**

```bash
bin/rails test:system TEST=test/system/spot_scenario_test.rb
```

Expected: all 4 tests pass. Fix any failures before proceeding.

- [ ] **Step 4: Run the full test suite to check for regressions**

```bash
bin/rails test
```

Expected: no new failures.

- [ ] **Step 5: Commit**

```bash
git add test/system/spot_scenario_test.rb
git commit -m "test(spot-scenario): system tests for calculator flows"
```

---

## Self-Review Checklist

- [x] **Spec coverage:**
  - Collapsible panel below positions table — Task 2 ✓
  - Ephemeral (no persistence) — no save endpoints, resets on toggle ✓
  - Linked cash % ↔ budget inputs — Task 3 ✓
  - Manual mode: sliders, live ROI, budget clamping, progress bar — Task 4 ✓
  - Optimize: fixed target algorithm with prioritization — Task 5 ✓
  - Optimize: best achievable floor via binary search — Task 6 ✓
  - Mode toggle (fixed / floor) — Task 5–6 ✓
  - Position checkboxes — Task 5 ✓
  - Status badges (Target met / Already past / Budget exhausted / Equalized) — Task 5–6 ✓
  - Edge cases (no price → disabled, risk-free → excluded, budget=0 → disabled) — Task 4–5 ✓
  - `frontend-design` skill invocation — Task 2 ✓

- [x] **No placeholders** — all code blocks are complete

- [x] **Type consistency:**
  - `_calcProjectedRoi` is called in Tasks 4, 5, 6 consistently
  - `_calcInjectionNeeded` is called in Tasks 5, 6 consistently
  - `_renderOptimizeResults` signature `(results, budget)` is consistent across Tasks 5, 6
  - Stimulus target names match between partial (Task 2) and controller (Tasks 3–6)
