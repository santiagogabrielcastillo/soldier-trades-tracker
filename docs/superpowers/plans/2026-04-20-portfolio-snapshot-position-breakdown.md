# Portfolio Snapshot Position Breakdown Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Capture per-position allocation data (% and value) in each portfolio snapshot and display it as a stacked area chart plus expandable table rows on the Performance tab.

**Architecture:** Add a `positions_data` JSONB column to `stock_portfolio_snapshots`, populate it in `Stocks::PortfolioSnapshotService` during the existing price-fetch pass (no extra API calls), expose it via a `positions_breakdown` reader on the model, and render it in the Performance tab view with a new stacked area chart (via Chart.js in the existing `stocks_charts_controller.js`) and expandable `<details>` rows.

**Tech Stack:** Rails 7, PostgreSQL (JSONB), Chart.js 4.5.1 + `chartjs-plugin-datalabels`, Stimulus, Tailwind CSS

---

## File Map

| File | Change |
|------|--------|
| `db/migrate/20260420120000_add_positions_data_to_stock_portfolio_snapshots.rb` | Create — adds `positions_data jsonb` column |
| `app/models/stock_portfolio_snapshot.rb` | Modify — add `positions_breakdown` reader |
| `app/services/stocks/portfolio_snapshot_service.rb` | Modify — compute and persist positions_data |
| `app/controllers/stocks_controller.rb` | Modify — build `@allocation_series` for the performance view |
| `app/views/stocks/index.html.erb` | Modify — allocation chart + expandable snapshot rows |
| `app/javascript/controllers/stocks_charts_controller.js` | Modify — add `renderAllocation`, persistent pie labels |
| `config/importmap.rb` | Modify — pin `chartjs-plugin-datalabels` |
| `test/models/stock_portfolio_snapshot_test.rb` | Modify — add `positions_breakdown` tests |
| `test/services/stocks/portfolio_snapshot_service_test.rb` | Create — test positions_data capture |

---

## Task 1: Migration — add positions_data column

**Files:**
- Create: `db/migrate/20260420120000_add_positions_data_to_stock_portfolio_snapshots.rb`

- [ ] **Step 1: Generate migration**

```bash
bin/rails generate migration AddPositionsDataToStockPortfolioSnapshots positions_data:jsonb
```

- [ ] **Step 2: Open the generated file and set a default of `[]`**

The generated file will be at `db/migrate/<timestamp>_add_positions_data_to_stock_portfolio_snapshots.rb`. Edit it to:

```ruby
class AddPositionsDataToStockPortfolioSnapshots < ActiveRecord::Migration[7.2]
  def change
    add_column :stock_portfolio_snapshots, :positions_data, :jsonb, default: [], null: false
  end
end
```

- [ ] **Step 3: Run the migration**

```bash
bin/rails db:migrate
```

Expected output includes: `AddPositionsDataToStockPortfolioSnapshots: migrated`

- [ ] **Step 4: Commit**

```bash
git add db/migrate/ db/schema.rb
git commit -m "feat: add positions_data jsonb column to stock_portfolio_snapshots"
```

---

## Task 2: Model — positions_breakdown reader

**Files:**
- Modify: `app/models/stock_portfolio_snapshot.rb`
- Modify: `test/models/stock_portfolio_snapshot_test.rb`

- [ ] **Step 1: Write the failing test**

Add to `test/models/stock_portfolio_snapshot_test.rb` inside the class, before the `private` section:

```ruby
# --- positions_breakdown ---

test "positions_breakdown returns empty array when positions_data is empty" do
  snapshot = build_snapshot(total_value: "100", cash_flow: "0")
  snapshot.positions_data = []
  assert_equal [], snapshot.positions_breakdown
end

test "positions_breakdown returns array of hashes with string keys" do
  snapshot = build_snapshot(total_value: "100", cash_flow: "0")
  snapshot.positions_data = [
    { "ticker" => "AAPL", "value" => 6000.0, "pct_of_total" => 60.0 },
    { "ticker" => "CASH", "value" => 4000.0, "pct_of_total" => 40.0 }
  ]
  result = snapshot.positions_breakdown
  assert_equal 2, result.size
  assert_equal "AAPL", result.first["ticker"]
  assert_equal 60.0,   result.first["pct_of_total"]
end
```

- [ ] **Step 2: Run the tests to confirm they fail**

```bash
bin/rails test test/models/stock_portfolio_snapshot_test.rb
```

Expected: 2 failures mentioning `NoMethodError: undefined method 'positions_breakdown'`

- [ ] **Step 3: Add `positions_breakdown` to the model**

Replace the full content of `app/models/stock_portfolio_snapshot.rb` with:

```ruby
# frozen_string_literal: true

class StockPortfolioSnapshot < ApplicationRecord
  belongs_to :stock_portfolio

  SOURCES = %w[weekly monthly manual].freeze

  validates :total_value, presence: true, numericality: true
  validates :cash_flow, presence: true, numericality: true
  validates :recorded_at, presence: true
  validates :source, inclusion: { in: SOURCES }

  scope :ordered, -> { order(:recorded_at) }

  def deposit?
    cash_flow.to_d.positive?
  end

  def withdrawal?
    cash_flow.to_d.negative?
  end

  def snapshot_only?
    cash_flow.to_d.zero?
  end

  def positions_breakdown
    Array(positions_data)
  end
end
```

- [ ] **Step 4: Run the tests to confirm they pass**

```bash
bin/rails test test/models/stock_portfolio_snapshot_test.rb
```

Expected: all green

- [ ] **Step 5: Commit**

```bash
git add app/models/stock_portfolio_snapshot.rb test/models/stock_portfolio_snapshot_test.rb
git commit -m "feat: add positions_breakdown reader to StockPortfolioSnapshot"
```

---

## Task 3: Service — capture positions_data during snapshot

**Files:**
- Modify: `app/services/stocks/portfolio_snapshot_service.rb`
- Create: `test/services/stocks/portfolio_snapshot_service_test.rb`

- [ ] **Step 1: Write the failing test**

Create `test/services/stocks/portfolio_snapshot_service_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

module Stocks
  class PortfolioSnapshotServiceTest < ActiveSupport::TestCase
    setup do
      @user = users(:one)
      @portfolio = @user.stock_portfolios.create!(name: "Snapshot Svc Test", market: "us", default: false)
    end

    test "creates snapshot with empty positions_data when no open positions" do
      Stocks::PositionStateService.stub(:call, []) do
        Stocks::CashBalanceService.stub(:call, BigDecimal("5000")) do
          snap = Stocks::PortfolioSnapshotService.call(stock_portfolio: @portfolio)
          assert_equal 1, snap.positions_breakdown.size
          cash_entry = snap.positions_breakdown.find { |p| p["ticker"] == "CASH" }
          assert_not_nil cash_entry
          assert_in_delta 100.0, cash_entry["pct_of_total"], 0.01
        end
      end
    end

    test "creates snapshot with positions_data including open positions" do
      pos = OpenStruct.new(ticker: "AAPL", shares: BigDecimal("10"), open?: true)

      Stocks::PositionStateService.stub(:call, [pos]) do
        Stocks::CurrentPriceFetcher.stub(:call, { "AAPL" => BigDecimal("150") }) do
          Stocks::CashBalanceService.stub(:call, BigDecimal("500")) do
            snap = Stocks::PortfolioSnapshotService.call(stock_portfolio: @portfolio)

            assert_equal BigDecimal("2000"), snap.total_value  # 10*150 + 500

            aapl = snap.positions_breakdown.find { |p| p["ticker"] == "AAPL" }
            cash = snap.positions_breakdown.find { |p| p["ticker"] == "CASH" }

            assert_not_nil aapl
            assert_not_nil cash
            assert_in_delta 75.0, aapl["pct_of_total"], 0.01   # 1500/2000*100
            assert_in_delta 25.0, cash["pct_of_total"], 0.01   # 500/2000*100
          end
        end
      end
    end

    test "omits CASH entry when cash balance is zero" do
      pos = OpenStruct.new(ticker: "MSFT", shares: BigDecimal("5"), open?: true)

      Stocks::PositionStateService.stub(:call, [pos]) do
        Stocks::CurrentPriceFetcher.stub(:call, { "MSFT" => BigDecimal("200") }) do
          Stocks::CashBalanceService.stub(:call, BigDecimal("0")) do
            snap = Stocks::PortfolioSnapshotService.call(stock_portfolio: @portfolio)
            tickers = snap.positions_breakdown.map { |p| p["ticker"] }
            assert_not_includes tickers, "CASH"
          end
        end
      end
    end
  end
end
```

- [ ] **Step 2: Run the tests to confirm they fail**

```bash
bin/rails test test/services/stocks/portfolio_snapshot_service_test.rb
```

Expected: failures — `positions_data` not being set / wrong values

- [ ] **Step 3: Refactor the service to capture positions_data**

Replace the full content of `app/services/stocks/portfolio_snapshot_service.rb` with:

```ruby
# frozen_string_literal: true

module Stocks
  # Fetches current portfolio value and saves a StockPortfolioSnapshot.
  # cash_flow: amount deposited (+) or withdrawn (−) at this moment; 0 for pure snapshots.
  class PortfolioSnapshotService
    def self.call(stock_portfolio:, cash_flow: 0, source: "manual")
      new(stock_portfolio: stock_portfolio, cash_flow: cash_flow, source: source).call
    end

    def initialize(stock_portfolio:, cash_flow:, source:)
      @stock_portfolio = stock_portfolio
      @cash_flow = cash_flow.to_d
      @source = source
    end

    def call
      total_value = compute_portfolio_value
      @stock_portfolio.stock_portfolio_snapshots.create!(
        total_value: total_value,
        cash_flow: @cash_flow,
        recorded_at: Time.current,
        source: @source,
        positions_data: @positions_data
      )
    end

    private

    def compute_portfolio_value
      positions = Stocks::PositionStateService.call(stock_portfolio: @stock_portfolio)
      open_positions = positions.select(&:open?)
      position_entries = []

      market_value = if open_positions.any?
        tickers = open_positions.map(&:ticker).uniq
        prices = if @stock_portfolio.argentina?
          Stocks::ArgentineCurrentPriceFetcher.call(tickers: tickers, user: @stock_portfolio.user)
        else
          Stocks::CurrentPriceFetcher.call(tickers: tickers, user: @stock_portfolio.user)
        end
        open_positions.sum(BigDecimal("0")) do |pos|
          price = prices[pos.ticker]
          next BigDecimal("0") unless price
          value = price.to_d * pos.shares
          position_entries << { "ticker" => pos.ticker, "value" => value.to_f }
          value
        end
      else
        BigDecimal("0")
      end

      cash = Stocks::CashBalanceService.call(stock_portfolio: @stock_portfolio)
      position_entries << { "ticker" => "CASH", "value" => cash.to_f } if cash.nonzero?

      total = market_value + cash

      @positions_data = if total.positive?
        position_entries.map do |entry|
          entry.merge("pct_of_total" => (entry["value"] / total.to_f * 100).round(2))
        end
      else
        []
      end

      total
    end
  end
end
```

- [ ] **Step 4: Run the tests to confirm they pass**

```bash
bin/rails test test/services/stocks/portfolio_snapshot_service_test.rb
```

Expected: all green

- [ ] **Step 5: Commit**

```bash
git add app/services/stocks/portfolio_snapshot_service.rb test/services/stocks/portfolio_snapshot_service_test.rb
git commit -m "feat: capture per-position breakdown in PortfolioSnapshotService"
```

---

## Task 4: Controller — build allocation_series for Performance tab

**Files:**
- Modify: `app/controllers/stocks_controller.rb`

- [ ] **Step 1: Locate the performance case in the controller**

Open `app/controllers/stocks_controller.rb` and find the `when "performance"` branch:

```ruby
when "performance"
  @twr_series = Stocks::TwrCalculatorService.call(stock_portfolio: @stock_portfolio)
  @snapshots = @stock_portfolio.stock_portfolio_snapshots.ordered.to_a.reverse
```

- [ ] **Step 2: Add `@allocation_series` to the performance case**

Replace that block with:

```ruby
when "performance"
  @twr_series = Stocks::TwrCalculatorService.call(stock_portfolio: @stock_portfolio)
  @snapshots = @stock_portfolio.stock_portfolio_snapshots.ordered.to_a.reverse
  @allocation_series = build_allocation_series(@snapshots)
```

- [ ] **Step 3: Add the private helper method**

In the `private` section of `StocksController`, add:

```ruby
def build_allocation_series(snapshots)
  chronological = snapshots.select { |s| s.positions_breakdown.any? }.reverse
  return {} if chronological.size < 2

  all_tickers = chronological.flat_map { |s| s.positions_breakdown.map { |p| p["ticker"] } }.uniq

  {
    labels: chronological.map { |s| s.recorded_at.strftime("%b %d, %Y") },
    series: all_tickers.map do |ticker|
      {
        ticker: ticker,
        data: chronological.map do |s|
          entry = s.positions_breakdown.find { |p| p["ticker"] == ticker }
          entry ? entry["pct_of_total"] : 0
        end
      }
    end
  }
end
```

- [ ] **Step 4: Run the full test suite to check for regressions**

```bash
bin/rails test
```

Expected: all green (no controller tests exist for this path, but model/service tests should still pass)

- [ ] **Step 5: Commit**

```bash
git add app/controllers/stocks_controller.rb
git commit -m "feat: build allocation_series for Performance tab chart"
```

---

## Task 5: JavaScript — allocation chart + persistent pie labels

**Files:**
- Modify: `config/importmap.rb`
- Modify: `app/javascript/controllers/stocks_charts_controller.js`

- [ ] **Step 1: Pin chartjs-plugin-datalabels in the importmap**

Add to `config/importmap.rb`:

```ruby
pin "chartjs-plugin-datalabels", to: "https://cdn.jsdelivr.net/npm/chartjs-plugin-datalabels@2.2.0/dist/chartjs-plugin-datalabels.min.js"
```

- [ ] **Step 2: Update stocks_charts_controller.js**

Replace the full file with:

```js
import { Controller } from "@hotwired/stimulus"
import { Chart, registerables } from "chart.js"
import ChartDataLabels from "chartjs-plugin-datalabels"

Chart.register(...registerables, ChartDataLabels)

const PALETTE = [
  "#6366f1", "#f59e0b", "#10b981", "#3b82f6", "#ef4444",
  "#8b5cf6", "#ec4899", "#14b8a6", "#f97316", "#84cc16",
  "#06b6d4", "#a855f7", "#fb7185", "#34d399", "#fbbf24"
]

export default class extends Controller {
  static targets = ["pieCanvas", "pieEmpty", "barCanvas", "barEmpty", "twrCanvas", "twrEmpty", "allocationCanvas", "allocationEmpty"]
  static values = { data: Object }

  connect() {
    const data = this.dataValue || {}
    const pie = data.pie || []
    const bar = data.bar || []
    const twr = data.twr || []
    const allocation = data.allocation || {}

    if (pie.length > 0 && this.hasPieCanvasTarget) {
      this.renderPie(pie)
    } else if (this.hasPieEmptyTarget) {
      this.pieEmptyTarget.classList.remove("hidden")
    }

    if (bar.length > 0 && this.hasBarCanvasTarget) {
      this.renderBar(bar)
    } else if (this.hasBarEmptyTarget) {
      this.barEmptyTarget.classList.remove("hidden")
    }

    if (twr.length > 0 && this.hasTwrCanvasTarget) {
      this.renderTwr(twr)
    } else if (this.hasTwrEmptyTarget) {
      this.twrEmptyTarget.classList.remove("hidden")
    }

    if (allocation.series?.length >= 1 && this.hasAllocationCanvasTarget) {
      this.renderAllocation(allocation)
    } else if (this.hasAllocationEmptyTarget) {
      this.allocationEmptyTarget.classList.remove("hidden")
    }
  }

  disconnect() {
    if (this.pieChart) this.pieChart.destroy()
    if (this.barChart) this.barChart.destroy()
    if (this.twrChart) this.twrChart.destroy()
    if (this.allocationChart) this.allocationChart.destroy()
  }

  renderPie(pie) {
    const ctx = this.pieCanvasTarget.getContext("2d")
    this.pieChart = new Chart(ctx, {
      type: "doughnut",
      data: {
        labels: pie.map((d) => d.ticker),
        datasets: [{
          data: pie.map((d) => d.pct),
          backgroundColor: pie.map((_, i) => PALETTE[i % PALETTE.length]),
          borderWidth: 1,
          borderColor: "#fff"
        }]
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        plugins: {
          legend: { position: "right", labels: { boxWidth: 12, font: { size: 11 } } },
          tooltip: {
            callbacks: {
              label: (ctx) => ` ${ctx.label}: ${ctx.parsed.toFixed(1)}%`
            }
          },
          datalabels: {
            color: "#fff",
            font: { size: 10, weight: "bold" },
            formatter: (value) => value >= 5 ? `${value.toFixed(1)}%` : "",
            anchor: "center",
            align: "center"
          }
        }
      }
    })
  }

  renderTwr(twr) {
    const ctx = this.twrCanvasTarget.getContext("2d")
    const lastVal = twr[twr.length - 1]?.twr_pct ?? 0
    const color = lastVal >= 0 ? "rgb(5, 150, 105)" : "rgb(220, 38, 38)"
    this.twrChart = new Chart(ctx, {
      type: "line",
      data: {
        labels: twr.map((d) => d.date),
        datasets: [{
          label: "TWR",
          data: twr.map((d) => d.twr_pct),
          borderColor: color,
          backgroundColor: color.replace("rgb", "rgba").replace(")", ", 0.08)"),
          fill: true,
          tension: 0.2,
          pointRadius: 3
        }]
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        plugins: {
          legend: { display: false },
          tooltip: { callbacks: { label: (ctx) => ` ${ctx.parsed.y.toFixed(2)}%` } },
          datalabels: { display: false }
        },
        scales: {
          x: { type: "category" },
          y: { ticks: { callback: (v) => `${v}%` } }
        }
      }
    })
  }

  renderBar(bar) {
    const ctx = this.barCanvasTarget.getContext("2d")
    this.barChart = new Chart(ctx, {
      type: "bar",
      data: {
        labels: bar.map((d) => d.ticker),
        datasets: [{
          label: "Unrealized P&L",
          data: bar.map((d) => d.pct),
          backgroundColor: bar.map((d) => d.pct >= 0 ? "rgba(5, 150, 105, 0.7)" : "rgba(220, 38, 38, 0.7)"),
          borderColor: bar.map((d) => d.pct >= 0 ? "rgb(5, 150, 105)" : "rgb(220, 38, 38)"),
          borderWidth: 1
        }]
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        plugins: {
          legend: { display: false },
          tooltip: {
            callbacks: {
              label: (ctx) => ` ${ctx.parsed.y.toFixed(2)}%`
            }
          },
          datalabels: { display: false }
        },
        scales: {
          y: {
            beginAtZero: true,
            ticks: { callback: (v) => `${v}%` }
          }
        }
      }
    })
  }

  renderAllocation(allocation) {
    const ctx = this.allocationCanvasTarget.getContext("2d")
    const { labels, series } = allocation
    this.allocationChart = new Chart(ctx, {
      type: "line",
      data: {
        labels,
        datasets: series.map(({ ticker, data }, i) => ({
          label: ticker,
          data,
          backgroundColor: PALETTE[i % PALETTE.length] + "50",
          borderColor: PALETTE[i % PALETTE.length],
          fill: true,
          tension: 0.2,
          pointRadius: 3
        }))
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        plugins: {
          legend: { position: "bottom", labels: { boxWidth: 12, font: { size: 11 } } },
          tooltip: {
            callbacks: {
              label: (ctx) => ` ${ctx.dataset.label}: ${ctx.parsed.y.toFixed(1)}%`
            }
          },
          datalabels: { display: false }
        },
        scales: {
          x: { type: "category" },
          y: {
            stacked: true,
            min: 0,
            max: 100,
            ticks: { callback: (v) => `${v}%` }
          }
        }
      }
    })
  }
}
```

- [ ] **Step 3: Commit**

```bash
git add config/importmap.rb app/javascript/controllers/stocks_charts_controller.js
git commit -m "feat: add allocation stacked area chart and persistent pie labels"
```

---

## Task 6: View — allocation chart and expandable snapshot rows

**Files:**
- Modify: `app/views/stocks/index.html.erb`

The performance tab section starts at line 345 with `<% if @view == "performance" %>`.

- [ ] **Step 1: Replace the performance chart block with allocation + TWR charts**

Find this block (around line 386–396):

```erb
<% twr_data = { twr: @twr_series.map { |p| { date: p.date, twr_pct: p.twr_pct } } } %>
<%= content_tag :div,
      data: { controller: "stocks-charts", "stocks-charts-data-value": twr_data.to_json } do %>
  <div class="mb-6 rounded-lg border border-slate-200 bg-white p-4 shadow-sm">
    <p class="mb-3 text-sm font-medium text-slate-700">Time-Weighted Return (%)</p>
    <div class="h-56">
      <canvas data-stocks-charts-target="twrCanvas"></canvas>
      <p class="hidden text-sm text-slate-500" data-stocks-charts-target="twrEmpty">No snapshots yet. Record at least two entries to see the chart.</p>
    </div>
  </div>
<% end %>
```

Replace it with:

```erb
<% charts_data = {
  twr: @twr_series.map { |p| { date: p.date, twr_pct: p.twr_pct } },
  allocation: @allocation_series
} %>
<%= content_tag :div,
      data: { controller: "stocks-charts", "stocks-charts-data-value": charts_data.to_json } do %>
  <div class="mb-6 rounded-lg border border-slate-200 bg-white p-4 shadow-sm">
    <p class="mb-3 text-sm font-medium text-slate-700">Allocation over time (%)</p>
    <div class="h-56">
      <canvas data-stocks-charts-target="allocationCanvas"></canvas>
      <p class="hidden text-sm text-slate-500" data-stocks-charts-target="allocationEmpty">No snapshots with position data yet. Record at least two snapshots to see the chart.</p>
    </div>
  </div>
  <div class="mb-6 rounded-lg border border-slate-200 bg-white p-4 shadow-sm">
    <p class="mb-3 text-sm font-medium text-slate-700">Time-Weighted Return (%)</p>
    <div class="h-56">
      <canvas data-stocks-charts-target="twrCanvas"></canvas>
      <p class="hidden text-sm text-slate-500" data-stocks-charts-target="twrEmpty">No snapshots yet. Record at least two entries to see the chart.</p>
    </div>
  </div>
<% end %>
```

- [ ] **Step 2: Update the snapshot table columns to include an expand column**

Find the `DataTableComponent` call for snapshots (around line 399):

```erb
<%= render DataTableComponent.new(columns: [
  { label: "Date", classes: "text-left" },
  { label: "Type", classes: "text-left" },
  { label: "Cash flow", classes: "text-right" },
  { label: "Portfolio value", classes: "text-right" },
  { label: "Source", classes: "text-left" },
  { label: "", classes: "text-right" }
]) do |table| %>
```

Replace with (add a "Positions" column before the delete column):

```erb
<%= render DataTableComponent.new(columns: [
  { label: "Date", classes: "text-left" },
  { label: "Type", classes: "text-left" },
  { label: "Cash flow", classes: "text-right" },
  { label: "Portfolio value", classes: "text-right" },
  { label: "Source", classes: "text-left" },
  { label: "Positions", classes: "text-left" },
  { label: "", classes: "text-right" }
]) do |table| %>
```

- [ ] **Step 3: Update snapshot row cells to include the expandable positions breakdown**

Find the row block (around line 408):

```erb
<% @snapshots.each do |snap| %>
  <% table.with_row do %>
    <td class="whitespace-nowrap px-6 py-4 text-sm text-slate-700"><%= snap.recorded_at.strftime("%b %d, %Y %H:%M") %></td>
    ...
    <td class="whitespace-nowrap px-6 py-4 text-sm capitalize text-slate-500"><%= snap.source %></td>
    <td class="whitespace-nowrap px-6 py-4 text-right text-sm">
      <%= button_to "Delete", stocks_snapshot_path(id: snap.id, portfolio_id: @stock_portfolio.id),
            method: :delete,
            data: { turbo_confirm: "Delete this entry?" },
            class: "text-slate-400 hover:text-red-600 text-xs" %>
    </td>
  <% end %>
<% end %>
```

Replace the `<% @snapshots.each do |snap| %>` block with:

```erb
<% @snapshots.each do |snap| %>
  <% breakdown = snap.positions_breakdown %>
  <% table.with_row do %>
    <td class="whitespace-nowrap px-6 py-4 text-sm text-slate-700"><%= snap.recorded_at.strftime("%b %d, %Y %H:%M") %></td>
    <td class="whitespace-nowrap px-6 py-4 text-sm text-slate-700">
      <% if snap.deposit? %>
        <span class="inline-flex items-center rounded-full bg-emerald-50 px-2 py-0.5 text-xs font-medium text-emerald-700">Deposit</span>
      <% elsif snap.withdrawal? %>
        <span class="inline-flex items-center rounded-full bg-red-50 px-2 py-0.5 text-xs font-medium text-red-700">Withdrawal</span>
      <% else %>
        <span class="inline-flex items-center rounded-full bg-slate-100 px-2 py-0.5 text-xs font-medium text-slate-600">Snapshot</span>
      <% end %>
    </td>
    <td class="whitespace-nowrap px-6 py-4 text-right text-sm <%= snap.snapshot_only? ? 'text-slate-400' : (snap.deposit? ? 'text-emerald-600' : 'text-red-600') %>">
      <% if snap.snapshot_only? %>
        —
      <% elsif @stock_portfolio.argentina? %>
        <%= snap.deposit? ? "+" : "−" %><%= format_ars(snap.cash_flow.abs) %>
      <% else %>
        <%= snap.deposit? ? "+" : "−" %><%= format_money(snap.cash_flow.abs) %>
      <% end %>
    </td>
    <td class="whitespace-nowrap px-6 py-4 text-right text-sm text-slate-700">
      <%= @stock_portfolio.argentina? ? format_ars(snap.total_value) : format_money(snap.total_value) %>
    </td>
    <td class="whitespace-nowrap px-6 py-4 text-sm capitalize text-slate-500"><%= snap.source %></td>
    <td class="px-6 py-4 text-sm text-slate-700">
      <% if breakdown.any? %>
        <details class="group">
          <summary class="cursor-pointer list-none text-xs text-slate-500 hover:text-slate-800">
            <span class="group-open:hidden">&#9654; <%= breakdown.size %> positions</span>
            <span class="hidden group-open:inline">&#9660; hide</span>
          </summary>
          <table class="mt-2 w-full min-w-[18rem] text-xs">
            <thead>
              <tr class="text-slate-500">
                <th class="pb-1 text-left font-medium">Ticker</th>
                <th class="pb-1 text-right font-medium">Value</th>
                <th class="pb-1 text-right font-medium">% of total</th>
              </tr>
            </thead>
            <tbody>
              <% breakdown.sort_by { |p| -p["pct_of_total"].to_f }.each do |pos| %>
                <tr class="border-t border-slate-100">
                  <td class="py-1 pr-4 font-semibold text-slate-800"><%= pos["ticker"] %></td>
                  <td class="py-1 pr-4 text-right text-slate-700">
                    <%= @stock_portfolio.argentina? ? format_ars(pos["value"]) : format_money(pos["value"]) %>
                  </td>
                  <td class="py-1 text-right text-slate-500"><%= number_to_percentage(pos["pct_of_total"], precision: 1) %></td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </details>
      <% else %>
        <span class="text-xs text-slate-400">—</span>
      <% end %>
    </td>
    <td class="whitespace-nowrap px-6 py-4 text-right text-sm">
      <%= button_to "Delete", stocks_snapshot_path(id: snap.id, portfolio_id: @stock_portfolio.id),
            method: :delete,
            data: { turbo_confirm: "Delete this entry?" },
            class: "text-slate-400 hover:text-red-600 text-xs" %>
    </td>
  <% end %>
<% end %>
```

- [ ] **Step 4: Start the dev server and manually verify**

```bash
./bin/dev
```

Navigate to Stocks → Performance tab. Verify:
1. "Allocation over time (%)" chart appears above TWR (empty state shown if < 2 snapshots with data)
2. TWR chart still renders correctly
3. Old snapshots show "—" in the Positions column
4. Record a new snapshot — it should appear with an expandable "N positions" toggle
5. Expand the toggle to see Ticker / Value / % of Total sub-table, sorted by % desc
6. Navigate to Portfolio tab — pie chart now shows persistent % labels on slices ≥ 5%

- [ ] **Step 5: Commit**

```bash
git add app/views/stocks/index.html.erb
git commit -m "feat: add allocation chart and expandable position breakdown to Performance tab"
```
