# Valuation Sanity Check Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a standalone valuation page at `/stocks/valuation_check` that projects EPS and forward P/E for years 1–5 (price held constant) with color-coded cells, accessible from the valuations and watchlist tabs.

**Architecture:** Thin Rails controller loads `StockFundamental` + current price and passes pre-fill data to the view; all projection math runs client-side in a Stimulus controller that recalculates live on input. Entry points are "Sanity Check" links added to each row in the existing `_fundamentals_table` partial.

**Tech Stack:** Rails 7, Stimulus (importmap auto-loaded), Tailwind CSS, Minitest

---

## File Map

| Action | Path |
|--------|------|
| Modify | `config/routes.rb` |
| Create | `app/controllers/stocks/valuation_check_controller.rb` |
| Create | `app/views/stocks/valuation_check/show.html.erb` |
| Create | `app/javascript/controllers/valuation_check_controller.js` |
| Modify | `app/views/stocks/_fundamentals_table.html.erb` |
| Create | `test/controllers/stocks/valuation_check_controller_test.rb` |

---

## Task 1: Route + Controller

**Files:**
- Modify: `config/routes.rb`
- Create: `app/controllers/stocks/valuation_check_controller.rb`
- Create: `test/controllers/stocks/valuation_check_controller_test.rb`

- [ ] **Step 1: Write the failing controller tests**

Create `test/controllers/stocks/valuation_check_controller_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

module Stocks
  class ValuationCheckControllerTest < ActionDispatch::IntegrationTest
    setup do
      @user = users(:one)
      @user.update!(password: "password", password_confirmation: "password")
    end

    test "show requires authentication" do
      get stocks_valuation_check_path
      assert_redirected_to login_path
    end

    test "show renders successfully without ticker" do
      sign_in_as(@user)
      get stocks_valuation_check_path
      assert_response :success
    end

    test "show renders successfully with valid ticker" do
      sign_in_as(@user)
      Stocks::CurrentPriceFetcher.stub(:call, { "AAPL" => BigDecimal("160") }) do
        get stocks_valuation_check_path(ticker: "AAPL")
      end
      assert_response :success
    end

    test "show pre-fills fwd_eps from fundamental and price" do
      sign_in_as(@user)
      Stocks::CurrentPriceFetcher.stub(:call, { "AAPL" => BigDecimal("160") }) do
        get stocks_valuation_check_path(ticker: "AAPL")
      end
      # AAPL fixture: fwd_pe: 25.1, so fwd_eps = 160 / 25.1 ≈ 6.37
      assert_select "input[name='fwd_eps']" do |inputs|
        assert inputs.first["value"].to_f.round(2) == 6.37
      end
    end

    test "show renders with blank pre-fill when no fundamental exists" do
      sign_in_as(@user)
      Stocks::CurrentPriceFetcher.stub(:call, {}) do
        get stocks_valuation_check_path(ticker: "NOPE")
      end
      assert_response :success
    end

    private

    def sign_in_as(user)
      post login_path, params: { email: user.email, password: "password" }
      follow_redirect!
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
bin/rails test test/controllers/stocks/valuation_check_controller_test.rb
```

Expected: errors about uninitialized constant or missing route.

- [ ] **Step 3: Add route**

In `config/routes.rb`, after the existing stocks analysis route (line 55), add:

```ruby
  get "stocks/valuation_check", to: "stocks/valuation_check#show", as: :stocks_valuation_check
```

- [ ] **Step 4: Create the controller**

Create `app/controllers/stocks/valuation_check_controller.rb`:

```ruby
# frozen_string_literal: true

module Stocks
  class ValuationCheckController < ApplicationController
    def show
      @ticker = params[:ticker].to_s.strip.upcase.presence
      @price = nil
      @fwd_eps = nil

      if @ticker
        fundamental = StockFundamental.find_by(ticker: @ticker)
        prices = Stocks::CurrentPriceFetcher.call(tickers: [@ticker])
        @price = prices[@ticker]

        if @price && fundamental&.fwd_pe&.positive?
          @fwd_eps = (@price / fundamental.fwd_pe).round(2)
        end
      end
    end
  end
end
```

- [ ] **Step 5: Create a minimal view so tests don't blow up on missing template**

Create `app/views/stocks/valuation_check/show.html.erb` with just a placeholder for now:

```erb
<p>placeholder</p>
<input type="hidden" name="fwd_eps" value="<%= @fwd_eps %>">
```

- [ ] **Step 6: Run tests to verify they pass**

```bash
bin/rails test test/controllers/stocks/valuation_check_controller_test.rb
```

Expected: all 5 tests pass.

- [ ] **Step 7: Commit**

```bash
git add config/routes.rb \
        app/controllers/stocks/valuation_check_controller.rb \
        app/views/stocks/valuation_check/show.html.erb \
        test/controllers/stocks/valuation_check_controller_test.rb
git commit -m "feat(valuation-check): route, controller, and tests"
```

---

## Task 2: View

**Files:**
- Modify: `app/views/stocks/valuation_check/show.html.erb`

- [ ] **Step 1: Replace placeholder with the full view**

Replace the contents of `app/views/stocks/valuation_check/show.html.erb`:

```erb
<%= render BreadcrumbComponent.new(items: [
  { label: "Stocks", url: stocks_path(view: "valuations") },
  { label: @ticker.present? ? "Sanity Check — #{@ticker}" : "Sanity Check" }
]) %>

<div class="mx-auto max-w-2xl">
  <div class="rounded-lg border border-slate-200 bg-white shadow-sm">
    <div class="border-b border-slate-200 px-6 py-4">
      <h1 class="text-base font-semibold text-slate-900">Valuation Sanity Check</h1>
      <p class="mt-0.5 text-sm text-slate-500">What does the P/E look like in 1–5 years if the price stays flat?</p>
    </div>

    <div class="px-6 py-5"
         data-controller="valuation-check"
         data-valuation-check-price-value="<%= @price&.to_f || '' %>"
         data-valuation-check-fwd-eps-value="<%= @fwd_eps&.to_f || '' %>">

      <%# Inputs %>
      <div class="grid grid-cols-3 gap-4 mb-6">
        <div>
          <label class="block text-xs font-medium text-slate-600 mb-1">Current Price ($)</label>
          <input type="number"
                 step="0.01"
                 min="0.01"
                 name="price"
                 placeholder="e.g. 160"
                 value="<%= @price&.to_f %>"
                 data-valuation-check-target="priceInput"
                 data-action="input->valuation-check#calculate"
                 class="w-full rounded-md border border-slate-300 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-slate-500">
        </div>
        <div>
          <label class="block text-xs font-medium text-slate-600 mb-1">Forward EPS ($)</label>
          <input type="number"
                 step="0.01"
                 min="0.01"
                 name="fwd_eps"
                 placeholder="e.g. 5.00"
                 value="<%= @fwd_eps&.to_f %>"
                 data-valuation-check-target="fwdEpsInput"
                 data-action="input->valuation-check#calculate"
                 class="w-full rounded-md border border-slate-300 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-slate-500">
        </div>
        <div>
          <label class="block text-xs font-medium text-slate-600 mb-1">Annual EPS Growth (%)</label>
          <input type="number"
                 step="0.1"
                 name="growth"
                 placeholder="e.g. 40"
                 value=""
                 data-valuation-check-target="growthInput"
                 data-action="input->valuation-check#calculate"
                 class="w-full rounded-md border border-slate-300 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-slate-500">
        </div>
      </div>

      <%# Error message %>
      <p data-valuation-check-target="errorMessage"
         class="hidden text-sm text-red-600 mb-4">Enter valid inputs (price and EPS must be positive).</p>

      <%# Projection table %>
      <div data-valuation-check-target="tableWrapper" class="hidden">
        <table class="w-full text-sm">
          <thead>
            <tr class="border-b border-slate-200">
              <th class="py-2 pr-4 text-left text-xs font-medium text-slate-500 uppercase tracking-wide">Year</th>
              <th class="py-2 pr-4 text-right text-xs font-medium text-slate-500 uppercase tracking-wide">Projected EPS</th>
              <th class="py-2 text-right text-xs font-medium text-slate-500 uppercase tracking-wide">P/E at current price</th>
            </tr>
          </thead>
          <tbody data-valuation-check-target="tableBody">
          </tbody>
        </table>

        <div class="mt-4 flex flex-wrap items-center gap-x-4 gap-y-1 text-xs text-slate-400">
          <span class="flex items-center gap-1"><span class="inline-block h-2.5 w-2.5 rounded-sm bg-red-100"></span> &gt; 30x expensive</span>
          <span class="flex items-center gap-1"><span class="inline-block h-2.5 w-2.5 rounded-sm bg-yellow-100"></span> 15–30x fair</span>
          <span class="flex items-center gap-1"><span class="inline-block h-2.5 w-2.5 rounded-sm bg-green-100"></span> &lt; 15x attractive</span>
          <span class="flex items-center gap-1"><span class="inline-block h-2.5 w-2.5 rounded-sm bg-emerald-200"></span> &lt; 10x gift</span>
        </div>
      </div>

    </div>
  </div>
</div>
```

- [ ] **Step 2: Boot the dev server and verify the page loads**

```bash
./bin/dev
```

Visit `http://localhost:5000/stocks/valuation_check` — expect to see the form with blank inputs. Visit `http://localhost:5000/stocks/valuation_check?ticker=AAPL` — expect price and EPS pre-filled (requires Finnhub API key in dev; if not configured, inputs may be blank — that's acceptable).

- [ ] **Step 3: Commit**

```bash
git add app/views/stocks/valuation_check/show.html.erb
git commit -m "feat(valuation-check): view with form and table skeleton"
```

---

## Task 3: Stimulus Controller

**Files:**
- Create: `app/javascript/controllers/valuation_check_controller.js`

- [ ] **Step 1: Create the Stimulus controller**

Create `app/javascript/controllers/valuation_check_controller.js`:

```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["priceInput", "fwdEpsInput", "growthInput", "tableBody", "tableWrapper", "errorMessage"]

  connect() {
    this.calculate()
  }

  calculate() {
    const price = parseFloat(this.priceInputTarget.value)
    const fwdEps = parseFloat(this.fwdEpsInputTarget.value)
    const growth = parseFloat(this.growthInputTarget.value)

    if (!price || !fwdEps || price <= 0 || fwdEps <= 0 || isNaN(growth)) {
      this.tableWrapperTarget.classList.add("hidden")
      const hasAnyInput = this.priceInputTarget.value || this.fwdEpsInputTarget.value || this.growthInputTarget.value
      this.errorMessageTarget.classList.toggle("hidden", !hasAnyInput)
      return
    }

    this.errorMessageTarget.classList.add("hidden")
    this.tableWrapperTarget.classList.remove("hidden")

    const growthRate = growth / 100
    const rows = Array.from({ length: 5 }, (_, i) => {
      const year = i + 1
      const eps = fwdEps * Math.pow(1 + growthRate, year)
      const pe = price / eps
      return { year, eps, pe }
    })

    this.tableBodyTarget.innerHTML = rows.map(({ year, eps, pe }) => `
      <tr class="border-b border-slate-100">
        <td class="py-3 pr-4 text-slate-700 font-medium">Year ${year}</td>
        <td class="py-3 pr-4 text-right text-slate-700">$${eps.toFixed(2)}</td>
        <td class="py-3 text-right font-semibold ${this._peClass(pe)} rounded px-2">${pe.toFixed(1)}x</td>
      </tr>
    `).join("")
  }

  _peClass(pe) {
    if (pe < 10) return "bg-emerald-100 text-emerald-800"
    if (pe < 15) return "bg-green-100 text-green-800"
    if (pe <= 30) return "bg-yellow-100 text-yellow-800"
    return "bg-red-100 text-red-800"
  }
}
```

- [ ] **Step 2: Open the browser and verify live calculation**

Visit `http://localhost:5000/stocks/valuation_check`. Enter:
- Price: `160`
- Forward EPS: `5`
- Growth: `40`

Expected table:

| Year | EPS    | P/E        |
|------|--------|------------|
| 1    | $7.00  | 22.9x (yellow) |
| 2    | $9.80  | 16.3x (yellow) |
| 3    | $13.72 | 11.7x (green)  |
| 4    | $19.21 | 8.3x (bright green) |
| 5    | $26.89 | 5.9x (bright green) |

- [ ] **Step 3: Verify error state**

Clear the Growth field — table should hide and "Enter valid inputs" message should appear.

- [ ] **Step 4: Commit**

```bash
git add app/javascript/controllers/valuation_check_controller.js
git commit -m "feat(valuation-check): stimulus controller with live P/E projection"
```

---

## Task 4: Entry Points in Fundamentals Table

**Files:**
- Modify: `app/views/stocks/_fundamentals_table.html.erb`

- [ ] **Step 1: Add "Sanity Check" column header**

In `app/views/stocks/_fundamentals_table.html.erb`, the `DataTableComponent` columns array starts at line 18. Add a new column at the end of the array (before the closing `]`), after the `sales_qq` column entry and before the watchlist conditional:

Find:
```ruby
  { label: "Sales Q/Q",  classes: "text-right" },
  *(watchlist_items ? [{ label: "", classes: "text-right" }] : [])
```

Replace with:
```ruby
  { label: "Sales Q/Q",  classes: "text-right" },
  { label: "",           classes: "text-right" },
  *(watchlist_items ? [{ label: "", classes: "text-right" }] : [])
```

- [ ] **Step 2: Add "Sanity Check" cell to each row**

In the same file, the watchlist remove button cell is at the bottom of the row block (around line 130). Add the sanity check cell just before it:

Find:
```erb
      <% if watchlist_items %>
        <td class="whitespace-nowrap px-6 py-4 text-right">
          <%= button_to "Remove", stocks_watchlist_item_path(watchlist_items[ticker]),
```

Replace with:
```erb
      <td class="whitespace-nowrap px-6 py-4 text-right">
        <%= link_to "Sanity Check", stocks_valuation_check_path(ticker: ticker),
              class: "text-xs font-medium text-indigo-600 hover:text-indigo-800 hover:underline" %>
      </td>
      <% if watchlist_items %>
        <td class="whitespace-nowrap px-6 py-4 text-right">
          <%= button_to "Remove", stocks_watchlist_item_path(watchlist_items[ticker]),
```

- [ ] **Step 3: Verify in the browser**

Visit `http://localhost:5000/stocks?view=valuations` (or `?view=watchlist`). Verify:
- A "Sanity Check" column appears on every row
- Clicking it navigates to `/stocks/valuation_check?ticker=TICKER` with pre-filled price and EPS

- [ ] **Step 4: Commit**

```bash
git add app/views/stocks/_fundamentals_table.html.erb
git commit -m "feat(valuation-check): add sanity check entry point to fundamentals table"
```

---

## Task 5: Full Test Run + Final Verification

- [ ] **Step 1: Run the full test suite**

```bash
bin/rails test
```

Expected: all tests pass (no regressions).

- [ ] **Step 2: Verify AMD example end-to-end**

If you have AMD in your fundamentals, navigate to `/stocks/valuation_check?ticker=AMD`. If not, go to `/stocks/valuation_check` and enter manually:
- Price: `160`, Forward EPS: `5`, Growth: `40`

Confirm year 4 shows ~8.3x with bright green background.

- [ ] **Step 3: Verify error state edge cases**

- Enter price = 0 → error shown, table hidden
- Enter negative EPS → error shown
- Enter growth = 0 → valid, flat EPS rows, constant P/E

- [ ] **Step 4: Final commit if any cleanup needed, else done**

```bash
bin/rails test
git status
```
