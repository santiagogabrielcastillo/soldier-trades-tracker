# Per-Ticker Stock Analysis — Design Spec

**Date:** 2026-04-13
**Status:** Approved

## Overview

Replace the single "Analyze all" button with a per-row "Analyze" button on both the valuations and watchlist views. Each button triggers AI analysis for exactly one ticker.

## What Changes

### Remove
- `sync_analysis` controller action
- `collect_analysis_tickers` private method
- `POST stocks/sync_analysis` route
- The "Analyze" button at the top of `_fundamentals_table.html.erb`
- The `analyze_url` local variable passed to the partial from both views

### Add
- `POST stocks/analyze/:ticker` route → `stocks#analyze_ticker`
- `analyze_ticker` controller action
- Per-row "Analyze" button in the AI Rating cell of the fundamentals table

## Route

```ruby
post "stocks/analyze/:ticker", to: "stocks#analyze_ticker", as: :stocks_analyze_ticker
```

Ticker goes in the path because it is the resource being acted on, consistent with how `:id` is used in `stocks_watchlist_item`.

## Controller Action

```ruby
def analyze_ticker
  ticker = params[:ticker].to_s.strip.upcase
  allowed = allowed_analysis_tickers
  unless allowed.include?(ticker)
    redirect_back fallback_location: stocks_path, alert: "Ticker not found." and return
  end
  Stocks::SyncStockAnalysisJob.perform_later(current_user.id, [ticker])
  redirect_back fallback_location: stocks_path, notice: "Analysis started — refresh in a moment."
end
```

`allowed_analysis_tickers` (private) returns the union of the user's open position tickers and watchlist tickers. This prevents enqueuing a job for an arbitrary ticker submitted by a malicious request.

```ruby
def allowed_analysis_tickers
  portfolio = StockPortfolio.find_or_create_default_for(current_user)
  open = Stocks::PositionStateService.call(stock_portfolio: portfolio)
           .select(&:open?).map(&:ticker)
  watchlist = current_user.watchlist_tickers.pluck(:ticker)
  (open + watchlist).uniq
end
```

The Gemini key guard is already enforced by `SyncStockAnalysisJob#perform` (returns early if no key), so no explicit check is needed in the controller.

## View: `_fundamentals_table.html.erb`

### Signature change

Remove the `analyze_url` local:

```erb
<%# locals: (tickers:, fundamentals:, sync_url:, watchlist_items: nil, analyses: {}) %>
```

### Header area

Remove the entire `if analyze_url && current_user.gemini_api_key_configured?` block.

### AI Rating cell

When `current_user.gemini_api_key_configured?` and no analysis exists, render a per-row "Analyze" button instead of the `—` dash:

```erb
<% if analysis %>
  <%# badge — unchanged %>
<% elsif current_user.gemini_api_key_configured? %>
  <%= button_to "Analyze", stocks_analyze_ticker_path(ticker),
        method: :post,
        class: "rounded-md bg-indigo-600 px-2 py-0.5 text-xs font-medium text-white hover:bg-indigo-500" %>
<% else %>
  <%= link_to "Configure AI", settings_path, ... %>
<% end %>
```

When analysis exists the badge is shown as before — no re-analyze button (out of scope).

## Callers of `_fundamentals_table` partial

The partial is rendered in `stocks/index.html.erb` for both the `valuations` and `watchlist` views. Both calls currently pass `analyze_url:`. Remove that argument from both render calls.

## `SyncStockAnalysisJob`

No changes. The job already accepts an array of tickers; passing `[ticker]` works as-is.

## Tests

- **Controller test:** `analyze_ticker` with a valid ticker enqueues the job; with an unknown ticker redirects with alert; requires authentication.
- **No view tests needed** — the partial change is straightforward HTML.

## Out of Scope

- Re-analyze button when analysis already exists
- Rate-limit feedback to the user (job errors are logged server-side)
