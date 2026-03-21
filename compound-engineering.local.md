---
review_agents: [kieran-rails-reviewer, dhh-rails-reviewer, code-simplicity-reviewer, security-sentinel, performance-oracle, architecture-strategist]
plan_review_agents: [kieran-rails-reviewer, code-simplicity-reviewer]
---

# Review Context

Project-specific review instructions for all review agents during /ce:review and /ce:work.

## Project Overview

Crypto futures trading portfolio tracker built on Rails 7.2 with PostgreSQL. Syncs trades from Binance and BingX exchanges, aggregates them into positions, and computes P&L/ROI metrics.

## Key Review Notes

### Financial Accuracy
- All P&L, ROI, and margin calculations must be reviewed for precision — use `BigDecimal` or ensure float arithmetic does not introduce rounding errors in financial computations.
- `PositionSummary` is the core financial logic model — any changes here require extra scrutiny for correctness across LONG/SHORT and BOTH-chain trade scenarios.
- The deduplication strategy (`symbol + executed_at + side + net_amount`) is load-bearing — watch for changes that could introduce duplicate trades or silent data loss.

### Security
- Exchange API keys and secrets are stored with Rails 7.2 encryption — never log, serialize, or expose these in plain text.
- The app fetches data from external exchange APIs (Binance, BingX) — validate and sanitize all external responses before persisting.
- Extra scrutiny on input validation for any public-facing endpoints or CSV import flows (SpotAccount).

### Performance
- Watch for N+1 queries in dashboard and portfolio views — positions are read with associated trades via `PositionTrade` join table.
- `SyncDispatcherJob` and `SyncExchangeAccountJob` run on Solid Queue (PostgreSQL-backed, no Redis) — avoid patterns that could cause job pile-up or lock contention on the queue database.
- The `Positions::RebuildForAccountService` replaces all positions for an account on each sync — ensure bulk operations use appropriate batching.

### Frontend (Hotwire)
- Turbo Frames and Turbo Streams are used heavily — check for frame-busting issues when adding redirects or rendering non-Turbo responses.
- Stimulus controllers are used for UI interactivity — no Node build step, importmap-rails only. Do not introduce npm dependencies.
- Tailwind CSS only — no custom CSS frameworks or inline styles.

### Rails Conventions
- Follow DHH/Rails conventions: fat models, thin controllers, service objects only when genuinely needed.
- Background jobs use Solid Queue with two databases (`primary` for app data, `queue` for jobs) — do not mix queue and app data concerns.
- `UserPreference` is a key/value store for UI state — do not overload it with business logic.
- `Portfolio` enforces one `default: true` per user via `before_save :clear_other_defaults` — preserve this invariant.
- `ExchangeAccount` API credentials use Rails 7.2 native encryption — do not replace with custom encryption.

### CEDEAR / Argentina Market Mode
- The app recently added CEDEAR/Argentina stock market support alongside crypto futures — review agents should be aware that `SpotAccount` and related models may serve dual purposes.
