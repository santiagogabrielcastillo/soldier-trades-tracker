# Per-Ticker Stock Analysis — Design Spec

**Date:** 2026-04-13
**Status:** Approved

## Overview

Replace the single "Analyze all" button with a per-row "Analyze" button on both the valuations and watchlist views. Each button triggers AI analysis for exactly one ticker. When analysis exists, the badge shows a tooltip with the last analyzed timestamp and a "Re-analyze" button allows triggering a fresh analysis.

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

Three states:

**No analysis, Gemini configured** — render an "Analyze" button:

```erb
<% elsif current_user.gemini_api_key_configured? %>
  <%= button_to "Analyze", stocks_analyze_ticker_path(ticker),
        method: :post,
        class: "rounded-md bg-indigo-600 px-2 py-0.5 text-xs font-medium text-white hover:bg-indigo-500" %>
```

**Analysis exists, Gemini configured** — show the rating badge with a tooltip and a "Re-analyze" button beneath it:

```erb
<% if analysis %>
  <div class="group relative inline-block">
    <span class="inline-flex items-center rounded-full px-2 py-0.5 text-xs font-semibold uppercase tracking-wide <%= badge_class %>"
          title="Analyzed <%= time_ago_in_words(analysis.analyzed_at) %> ago">
      <%= analysis.rating %>
    </span>
    <p class="mt-1 text-xs text-slate-400">
      <%= time_ago_in_words(analysis.analyzed_at) %> ago
    </p>
    <%= button_to "Re-analyze", stocks_analyze_ticker_path(ticker),
          method: :post,
          class: "mt-1 text-xs font-medium text-indigo-500 hover:text-indigo-700 bg-transparent border-0 p-0 cursor-pointer" %>
  </div>
```

The timestamp is shown as a human-readable relative string (e.g. "3 days ago") directly below the badge. No custom JS tooltip — plain HTML `title` attribute provides the hover tooltip as a fallback with the same text, keeping the implementation simple.

**No Gemini key** — unchanged `Configure AI` link.

## Callers of `_fundamentals_table` partial

The partial is rendered in `stocks/index.html.erb` for both the `valuations` and `watchlist` views. Both calls currently pass `analyze_url:`. Remove that argument from both render calls.

## `SyncStockAnalysisJob`

No changes. The job already accepts an array of tickers; passing `[ticker]` works as-is.

## Tests

- **Controller test:** `analyze_ticker` with a valid ticker enqueues the job; with an unknown ticker redirects with alert; requires authentication.
- **No view tests needed** — the partial change is straightforward HTML.

## Out of Scope

- Rate-limit feedback to the user (job errors are logged server-side)
- Custom CSS tooltip (native `title` attribute is sufficient)
