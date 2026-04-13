# Per-Ticker Stock Analysis Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the single "Analyze all" button with a per-row "Analyze" / "Re-analyze" button in the fundamentals table, and show the last analyzed timestamp below the rating badge.

**Architecture:** Add a new `POST stocks/analyze/:ticker` route and `analyze_ticker` controller action that validates the ticker belongs to the user before enqueuing `SyncStockAnalysisJob` for a single ticker. The `_fundamentals_table` partial is updated to render per-row buttons and timestamp. The old `sync_analysis` route, action, and `collect_analysis_tickers` helper are deleted.

**Tech Stack:** Rails 8, Solid Queue, Tailwind CSS, Minitest

---

## Files

| File | Change |
|------|--------|
| `config/routes.rb` | Add `stocks/analyze/:ticker` route; remove `stocks/sync_analysis` |
| `app/controllers/stocks_controller.rb` | Add `analyze_ticker` + `allowed_analysis_tickers`; remove `sync_analysis` + `collect_analysis_tickers` |
| `app/views/stocks/_fundamentals_table.html.erb` | Remove `analyze_url` local + top button; update AI Rating cell with per-row buttons and timestamp |
| `app/views/stocks/index.html.erb` | Remove `analyze_url:` arg from both `render` calls |
| `test/controllers/stocks_controller_test.rb` | New file — controller tests for `analyze_ticker` |

---

## Task 1: Route + Controller Action

**Files:**
- Modify: `config/routes.rb`
- Modify: `app/controllers/stocks_controller.rb`

- [ ] **Step 1: Write the failing controller test**

Create `test/controllers/stocks_controller_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class StocksControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @user.update!(password: "password", password_confirmation: "password")
  end

  # --- analyze_ticker ---

  test "analyze_ticker redirects to login when not authenticated" do
    post stocks_analyze_ticker_path("AAPL")
    assert_redirected_to login_path
  end

  test "analyze_ticker enqueues job for valid open-position ticker" do
    sign_in_as(@user)

    # Stub allowed tickers so we don't need real positions/watchlist data
    StocksController.any_instance.stub(:allowed_analysis_tickers, ["AAPL"]) do
      assert_enqueued_with(job: Stocks::SyncStockAnalysisJob, args: [@user.id, ["AAPL"]]) do
        post stocks_analyze_ticker_path("AAPL")
      end
    end

    assert_redirected_to stocks_path
    assert_match "Analysis started", flash[:notice]
  end

  test "analyze_ticker redirects with alert for unknown ticker" do
    sign_in_as(@user)

    StocksController.any_instance.stub(:allowed_analysis_tickers, ["AAPL"]) do
      post stocks_analyze_ticker_path("UNKNOWN")
    end

    assert_redirected_to stocks_path
    assert_match "Ticker not found", flash[:alert]
  end

  private

  def sign_in_as(user)
    post login_path, params: { email: user.email, password: "password" }
    follow_redirect!
  end
end
```

- [ ] **Step 2: Run the test to confirm it fails with a routing error**

```bash
bin/rails test test/controllers/stocks_controller_test.rb
```

Expected: FAIL — `No route matches [POST] "/stocks/analyze/AAPL"`

- [ ] **Step 3: Add the new route and remove the old one**

In `config/routes.rb`, replace:

```ruby
post "stocks/sync_analysis",     to: "stocks#sync_analysis",     as: :stocks_sync_analysis
```

with:

```ruby
post "stocks/analyze/:ticker",   to: "stocks#analyze_ticker",    as: :stocks_analyze_ticker
```

- [ ] **Step 4: Add `analyze_ticker` and `allowed_analysis_tickers` to the controller**

In `app/controllers/stocks_controller.rb`, add the new action in the public section (after `sync_watchlist`):

```ruby
def analyze_ticker
  ticker = params[:ticker].to_s.strip.upcase
  unless allowed_analysis_tickers.include?(ticker)
    redirect_back fallback_location: stocks_path, alert: "Ticker not found." and return
  end
  Stocks::SyncStockAnalysisJob.perform_later(current_user.id, [ticker])
  redirect_back fallback_location: stocks_path, notice: "Analysis started — refresh in a moment."
end
```

Add `allowed_analysis_tickers` in the `private` section:

```ruby
def allowed_analysis_tickers
  portfolio = StockPortfolio.find_or_create_default_for(current_user)
  open = Stocks::PositionStateService.call(stock_portfolio: portfolio)
           .select(&:open?).map(&:ticker)
  watchlist = current_user.watchlist_tickers.pluck(:ticker)
  (open + watchlist).uniq
end
```

- [ ] **Step 5: Remove the old `sync_analysis` action and `collect_analysis_tickers` from the controller**

Delete the `sync_analysis` method:

```ruby
def sync_analysis
  tickers = collect_analysis_tickers
  if tickers.any?
    Stocks::SyncStockAnalysisJob.perform_later(current_user.id, tickers)
    notice = "Analysis started — refresh in a moment to see ratings."
  else
    notice = "No tickers to analyze."
  end
  redirect_back fallback_location: stocks_path, notice: notice
end
```

Delete the `collect_analysis_tickers` private method:

```ruby
def collect_analysis_tickers
  portfolio = StockPortfolio.find_or_create_default_for(current_user)
  open_tickers = Stocks::PositionStateService.call(stock_portfolio: portfolio)
                  .select(&:open?).map(&:ticker)
  watchlist_tickers = current_user.watchlist_tickers.pluck(:ticker)
  (open_tickers + watchlist_tickers).uniq
end
```

- [ ] **Step 6: Run the tests and confirm they pass**

```bash
bin/rails test test/controllers/stocks_controller_test.rb
```

Expected: 3 tests, 0 failures

- [ ] **Step 7: Commit**

```bash
git add config/routes.rb app/controllers/stocks_controller.rb test/controllers/stocks_controller_test.rb
git commit -m "feat(stocks): add analyze_ticker action; remove sync_analysis"
```

---

## Task 2: Update the View

**Files:**
- Modify: `app/views/stocks/_fundamentals_table.html.erb`
- Modify: `app/views/stocks/index.html.erb`

- [ ] **Step 1: Remove `analyze_url` from the partial signature and header**

In `app/views/stocks/_fundamentals_table.html.erb`, change line 1 from:

```erb
<%# locals: (tickers:, fundamentals:, sync_url:, watchlist_items: nil, analyze_url: nil, analyses: {}) %>
```

to:

```erb
<%# locals: (tickers:, fundamentals:, sync_url:, watchlist_items: nil, analyses: {}) %>
```

Then remove lines 15–19 (the top "Analyze" button block):

```erb
    <% if analyze_url && current_user.gemini_api_key_configured? %>
      <%= button_to "Analyze", analyze_url,
            method: :post,
            class: "rounded-md bg-indigo-600 px-3 py-1.5 text-sm font-medium text-white hover:bg-indigo-500 focus:outline-none focus:ring-2 focus:ring-indigo-500" %>
    <% end %>
```

- [ ] **Step 2: Update the AI Rating cell to support three states**

Replace the entire AI Rating `<td>` block (lines 46–63):

```erb
      <td class="whitespace-nowrap px-6 py-4 text-center text-sm">
        <% if analysis %>
          <% badge_class = case analysis.rating
             when "buy"   then "bg-emerald-100 text-emerald-800"
             when "hold"  then "bg-amber-100 text-amber-800"
             when "sell"  then "bg-red-100 text-red-800"
             else              "bg-slate-100 text-slate-700"
             end %>
          <span class="inline-flex items-center rounded-full px-2 py-0.5 text-xs font-semibold uppercase tracking-wide <%= badge_class %>"
                title="Analyzed <%= time_ago_in_words(analysis.analyzed_at) %> ago">
            <%= analysis.rating %>
          </span>
          <p class="mt-1 text-xs text-slate-400"><%= time_ago_in_words(analysis.analyzed_at) %> ago</p>
          <% if current_user.gemini_api_key_configured? %>
            <%= button_to "Re-analyze", stocks_analyze_ticker_path(ticker),
                  method: :post,
                  class: "mt-1 text-xs font-medium text-indigo-500 hover:text-indigo-700 bg-transparent border-0 p-0 cursor-pointer" %>
          <% end %>
        <% elsif current_user.gemini_api_key_configured? %>
          <%= button_to "Analyze", stocks_analyze_ticker_path(ticker),
                method: :post,
                class: "rounded-md bg-indigo-600 px-2 py-0.5 text-xs font-medium text-white hover:bg-indigo-500" %>
        <% else %>
          <%= link_to "Configure AI", settings_path,
                class: "text-xs font-medium text-indigo-600 hover:text-indigo-800 underline underline-offset-2" %>
        <% end %>
      </td>
```

- [ ] **Step 3: Remove `analyze_url:` from both render calls in `index.html.erb`**

Find the valuations render (around line 453) and remove the `analyze_url:` line:

```erb
      <%= render "stocks/fundamentals_table",
            tickers:       @positions.map(&:ticker),
            fundamentals:  @fundamentals,
            sync_url:      stocks_sync_fundamentals_path(portfolio_id: @stock_portfolio.id),
            analyses:      @analyses %>
```

Find the watchlist render (around line 475) and remove the `analyze_url:` line:

```erb
      <%= render "stocks/fundamentals_table",
            tickers:         @watchlist_tickers.map(&:ticker),
            fundamentals:    @fundamentals,
            sync_url:        stocks_watchlist_sync_path,
            watchlist_items: @watchlist_tickers.index_by(&:ticker),
            analyses:        @analyses %>
```

- [ ] **Step 4: Run the full test suite to catch any regressions**

```bash
bin/rails test
```

Expected: all existing tests pass (no reference to `stocks_sync_analysis_path` remains)

- [ ] **Step 5: Commit**

```bash
git add app/views/stocks/_fundamentals_table.html.erb app/views/stocks/index.html.erb
git commit -m "feat(stocks): per-row Analyze/Re-analyze buttons with analyzed_at timestamp"
```
