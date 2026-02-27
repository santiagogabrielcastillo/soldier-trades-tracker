# Plan: Codebase Refactor for Project Conventions

**Date:** 2026-02-26  
**Source:** `.cursor/rules/project-conventions.md` + full codebase audit

## Goal

Align the entire codebase with the project conventions (skinny controllers/models, business logic in service objects, exchange-agnostic job, smaller focused classes) before the project grows.

---

## Conventions File Fixes (Do First)

The conventions file was created from a template and has inconsistencies with this project:

| Issue | Fix |
|-------|-----|
| Duplicate YAML frontmatter (two `---` blocks) | Single frontmatter block. |
| "Boxful codebase" | Change to "soldier-trades-tracker" / "this project". |
| Convention 2: "interactor gem" / "actors" | This project does **not** use the interactor gem (Convention 1: minimize dependencies). Update to: **"Place business logic in service objects. Keep them small and atomic so they can be composed. Avoid adding the interactor gem unless there is a strong reason."** |
| Broken link: `checkbox_select_all_controller.js` | Remove or replace with a generic example (this project may not have that file). |

**Task:** Edit `.cursor/rules/project-conventions.md`: fix frontmatter, rename Boxful → this project, rewrite Convention 2 to "service objects" (no interactor), fix or remove the Convention 3 example link.

---

## Audit vs Conventions

### Convention 1: Minimize dependencies

- **Status:** OK. No interactor; Solid Queue, Pagy, bcrypt, Tailwind, etc. are in use. Plan keeps it that way (no new gems for refactor).

### Convention 2: Business logic in service objects

| Location | Current | Target |
|----------|---------|--------|
| **TradesController#index** | View selection, portfolio resolution, trades load, `PositionSummary.from_trades`, `assign_balance!`, pagy. | Extract to a service e.g. `Trades::IndexService` or `Trades::PortfolioViewService` that returns `{ view:, portfolio:, positions:, pagy:, ... }`. Controller only assigns instance vars and renders. |
| **DashboardsController#show** | Same pattern: trades, `PositionSummary.from_trades`, `assign_balance!`, summary stats. | Extract to e.g. `Dashboards::SummaryService` (portfolio or nil → summary data). Controller stays thin. |
| **ExchangeAccountsController#create** | Build, presence check, `linked_at`, save. | Optional: `ExchangeAccounts::CreateService` (params, user → build + set linked_at + save). Keeps create logic in one place. |
| **ExchangeAccountsController#sync** | provider_type check, can_sync?, perform_later. | After job is exchange-agnostic: "syncable?" can come from provider factory; enqueue via job. Service optional. |
| **SyncExchangeAccountJob#perform** | Full sync flow: find account, provider check, build client, fetch trades, calculator, persist, SyncRun. | Extract to e.g. `ExchangeAccounts::SyncService` (account) that does fetch + apply calculator + persist + SyncRun. Job only: find account, call service, rescue ApiError. |
| **SyncDispatcherJob** | user_due?, provider_type "bingx", can_sync?, enqueue. | After provider factory: "accounts that have a provider" instead of hardcoded "bingx". `user_due?` can stay or move to a small service. |
| **BingxClient** | Single ~325-line file: HTTP, orchestration, 3 fetchers, 3 normalizers, helpers, debug. | Split: HTTP layer, normalizers, orchestration (see below). |

### Convention 3: Turbo / Stimulus

- **Status:** Not audited in this plan. Recommendation: in a follow-up, verify views use Turbo/Stimulus where appropriate and remove or simplify heavy JS.

### Convention 4: Solid Queue

- **Status:** Already used. No change.

### Convention 5: Minitest + minimal fixtures

- **Status:** Minitest in use; fixtures are minimal (base cases). Job test creates account in setup for encryption—good. No refactor required.

### Convention 6: DB vs AR validations

- **Status:** Unique index on trades (account + reference); unique email on users. AR validations for presence, inclusion, custom (read_only_api_key). Recommendation: add `null: false` on `exchange_accounts.provider_type` if acceptable (currently nullable). Otherwise leave as is.

---

## Refactor Order and Scope

### Phase 1: Conventions file

- Update `.cursor/rules/project-conventions.md` as in "Conventions File Fixes" above.

### Phase 2: Exchange-agnostic job + BingxClient split

Implements the brainstorm: [2026-02-26-bingx-refactor-and-exchange-agnostic-job-brainstorm.md](../brainstorms/2026-02-26-bingx-refactor-and-exchange-agnostic-job-brainstorm.md).

1. **Provider factory**  
   - Add e.g. `Exchanges::ProviderForAccount` (or `Exchanges::ProviderRegistry`): given an `ExchangeAccount`, returns a client that responds to `fetch_my_trades(since:)`. For `provider_type == "bingx"` return `Exchanges::BingxClient.new(...)`.  
   - Job: remove `return unless account.provider_type == "bingx"` and `Exchanges::BingxClient.new(...)`. Use factory to get client; if nil, return (unsupported provider).  
   - Validator: use factory (or a “ping for account” that uses factory) so we don’t branch on `"bingx"` in the validator.  
   - Dispatcher: use “accounts that have a provider” (e.g. factory returns non-nil) or keep a list of supported provider types from the factory.  
   - Controller#sync: same idea—sync allowed if account has a provider; remove "Only BingX accounts can be synced" or make it "Only supported exchanges can be synced."

2. **BingxClient split**  
   - **HTTP/signing:** `Exchanges::Bingx::HttpClient` (or `Bingx::SignedRequest`) with `get(path, params)` → builds URI, signs, sends, handles 429/5xx/timeout/parse → raises `Exchanges::ApiError`.  
   - **Normalizers:** `Exchanges::Bingx::TradeNormalizer` (module or class) with `normalize_v1_order_to_trade`, `normalize_fill_to_trade`, `normalize_income_to_trade`.  
   - **BingxClient:** Keeps `fetch_my_trades`, the three `fetch_trades_from_*` methods, and `ping`; uses `HttpClient` and `TradeNormalizer`. File should drop to well under 150 lines.  
   - Optional: move debug helpers to a console-only module if you want the main client even smaller.

### Phase 3: Controller services (skinny controllers)

3. **Trades index**  
   - New service e.g. `Trades::IndexService.call(user:, view:, portfolio_id:, params:)` → `{ view:, portfolio:, trades:, positions:, pagy:, portfolios:, initial_balance: }`.  
   - Controller: call service, set instance variables from result, render.

4. **Dashboard summary**  
   - New service e.g. `Dashboards::SummaryService.call(user:)` → `{ exchange_accounts:, default_portfolio:, trades:, positions:, summary_label:, summary_date_range:, summary_period_pl:, summary_balance:, summary_position_count:, summary_trades_path: }`.  
   - Controller: call service, set instance variables, render.

### Phase 4: Exchange account create + sync flow

5. **ExchangeAccounts::CreateService** (optional)  
   - Input: user, params. Builds account, sets `linked_at`, runs validations (model still validates). Returns success + account or failure + errors. Controller calls service and redirects or re-renders.

6. **ExchangeAccounts::SyncService**  
   - Input: `ExchangeAccount`. Gets client from provider factory, fetches trades, applies FinancialCalculator for trade-style hashes, persists each trade (with RecordNotUnique rescue), creates SyncRun, updates `last_synced_at`. Raises `Exchanges::ApiError` on API failure.  
   - **SyncExchangeAccountJob:** finds account, calls `SyncService.call(account)`, rescues and logs. No sync logic in the job.

7. **SyncDispatcherJob**  
   - Replace `where(provider_type: "bingx")` with “accounts that have a provider” (e.g. `user.exchange_accounts.select { |a| Exchanges::ProviderForAccount.new(a).client }` or a scope if you add `supported_provider_types`).  
   - Optional: extract `user_due?(user, now)` to a small service e.g. `Users::SyncDueCheck`.

### Phase 5: Validator + controller sync

8. **Validator**  
   - Use provider factory: get client for account (or for provider_type + credentials); if client responds to `ping`, call it; otherwise assume valid (or not supported). Removes hardcoded "bingx" in validator.

9. **ExchangeAccountsController#sync**  
   - Replace "Only BingX accounts can be synced" with "This exchange is not supported for sync" when factory returns no client. Use same `can_sync?` and enqueue.

---

## File and Naming Conventions

- **Services:** `app/services/<domain>/<action_or_name>_service.rb` (e.g. `trades/index_service.rb`, `dashboards/summary_service.rb`, `exchange_accounts/sync_service.rb`).  
- **Exchanges:** Keep under `app/services/exchanges/`. BingX under `app/services/exchanges/bingx/` (e.g. `http_client.rb`, `trade_normalizer.rb`), main client stays `bingx_client.rb` or becomes `exchanges/bingx/client.rb` if you prefer.  
- **Single responsibility:** Each service does one thing; controllers only call services and render.

---

## Testing

- Existing tests for BingxClient, FinancialCalculator, SyncExchangeAccountJob must be updated after refactor (provider factory stub, possibly new service specs).  
- Add tests for new services (Trades::IndexService, Dashboards::SummaryService, ExchangeAccounts::SyncService) as needed.  
- Keep Minitest + fixtures; edge cases created in tests (per Convention 5).

---

## Summary Checklist

- [x] Conventions file: fix frontmatter, Boxful → this project, Convention 2 = service objects (no interactor), fix Convention 3 example.
- [x] Provider factory: `Exchanges::ProviderForAccount` (or equivalent); job, validator, dispatcher, controller#sync use it.
- [x] BingxClient: extract HttpClient, TradeNormalizer; BingxClient orchestrates only.
- [x] Trades::IndexService (or equivalent): TradesController#index delegates to it.
- [x] Dashboards::SummaryService: DashboardsController#show delegates to it.
- [x] ExchangeAccounts::SyncService: SyncExchangeAccountJob#perform delegates to it.
- [x] SyncDispatcherJob: use provider factory instead of `provider_type == "bingx"`.
- [x] ExchangeAccountKeyValidator: use provider factory for ping.
- [x] ExchangeAccountsController#sync: message and check via factory.
- [ ] Optional: ExchangeAccounts::CreateService, Users::SyncDueCheck.

---

## References

- Conventions: `.cursor/rules/project-conventions.md`
- Brainstorm (Bingx + job): `docs/brainstorms/2026-02-26-bingx-refactor-and-exchange-agnostic-job-brainstorm.md`
- Current BingxClient: `app/services/exchanges/bingx_client.rb`
- Current job: `app/jobs/sync_exchange_account_job.rb`
