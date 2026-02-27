# Brainstorm: BingxClient Refactor + Exchange-Agnostic Sync Job

**Date:** 2026-02-26

## What We're Building

1. **Refactor BingxClient** so it fits Rails conventions: smaller files, clear responsibilities, no oversized single class.
2. **Decouple SyncExchangeAccountJob from BingX** so the job is exchange-agnostic: it works with any provider type via a single abstraction (e.g. “get a client for this account” and “fetch trades”), without hardcoding `"bingx"` or `Exchanges::BingxClient`.

---

## Current State

**BingxClient (~325 lines)** currently does:

- **Transport:** `signed_get` (HMAC signing, Net::HTTP, timeouts, 429/5xx/parse → ApiError).
- **Orchestration:** `fetch_my_trades` (tries v1 full order → v2 fills → income; fallback lookback).
- **Data sources:** Three fetch methods with pagination (`fetch_trades_from_v1_full_order`, `fetch_trades_from_v2_fills`, `fetch_trades_from_income`).
- **Normalization:** Three normalizers (`normalize_v1_order_to_trade`, `normalize_fill_to_trade`, `normalize_income_to_trade`) turning BingX payloads into the shared hash shape.
- **Helpers:** `ok_response?`, `extract_list`, `executed_at_from`, `stablequote_pair?`.
- **Debug / ping:** `debug_fetch_*`, `debug_fetch_all_raw`, `self.ping`.

**Job coupling:**

- `return unless account.provider_type == "bingx"`.
- `Exchanges::BingxClient.new(api_key: ..., api_secret: ...)`.
- No use of `BaseProvider` as a polymorphic interface.

**Other coupling:**

- `ExchangeAccountKeyValidator` and `ExchangeAccountsController#sync` branch on `"bingx"`.
- `SyncDispatcherJob` uses `where(provider_type: "bingx")`.

---

## Why Refactor

- **Rails conventions:** Single large service files are hard to navigate and test. Splitting by responsibility (HTTP, normalization, orchestration) keeps classes small and focused.
- **Exchange-agnostic job:** The job should not know about BingX. Adding Binance (or another exchange) today would require editing the job, dispatcher, controller, and validator. A single “provider for account” abstraction lets the job stay unchanged.

---

## Approaches

### A: Extract HTTP + normalizers; provider factory for job (recommended)

**BingxClient:**

- Extract **HTTP/signing** into a small class (e.g. `Exchanges::Bingx::HttpClient`) used by the main client: build request, sign, send, handle 429/5xx/timeout/parse → ApiError. Keeps `signed_get` logic in one place.
- Extract **normalizers** into a dedicated object or module (e.g. `Exchanges::Bingx::TradeNormalizer`) with the three methods. BingxClient (or a “trade fetcher”) calls the normalizer; the main file stays orchestration + high-level fetch flow.
- Keep **orchestration** in `BingxClient`: `fetch_my_trades` and the three `fetch_trades_from_*` methods, but they call HttpClient and TradeNormalizer. Optionally extract the three fetchers into a single “TradeFetcher” class if the main file is still long.
- **Debug / ping:** Stay on `BingxClient` (delegate to HttpClient) or move to a console-only namespace if desired.

**Job / dispatcher / controller:**

- Introduce a **provider factory**: e.g. `Exchanges::ProviderForAccount.new(account).client` returns an object that responds to `fetch_my_trades(since:)` (and optionally `ping` for validation). For BingX, it returns a `BingxClient` instance; later, for Binance, it returns a Binance client.
- **Job:** No `provider_type == "bingx"`; no `BingxClient`. It gets the client from the factory, calls `fetch_my_trades(since:)`, then applies the existing trade-loop (calculator for trade-style, persist, RecordNotUnique rescue).
- **Validator:** Call the factory (or a “ping” entry point that uses the factory) so validation is per-provider without branching on string.
- **Dispatcher:** Either keep `where(provider_type: "bingx")` until a second exchange exists, or switch to “all accounts that have a provider implementation” (e.g. iterate accounts and skip if factory returns nil).

**Pros:** Clear split of responsibilities; job and validator become exchange-agnostic; adding a new exchange is “new client class + register in factory.”  
**Cons:** More files and indirection; factory must be consistent (e.g. credentials from account).

---

### B: Minimal split + job uses BaseProvider by name

**BingxClient:**

- Only split the **normalizers** into e.g. `Exchanges::Bingx::Normalizers` (module or class) to shrink the main file. Keep HTTP and orchestration in BingxClient.
- Optionally extract a thin **HttpClient** for `signed_get` if you want to test HTTP in isolation.

**Job:**

- Introduce a **factory or registry** that, given `provider_type`, returns the provider class (e.g. `Exchanges::BingxClient` for `"bingx"`). Job calls `provider_class.new(api_key: ..., api_secret: ...).fetch_my_trades(since:)` and never references BingxClient by name. So job is “exchange-agnostic” in the sense that it doesn’t hardcode BingX, but it still assumes every account has a provider class that can be instantiated with api_key/api_secret.

**Pros:** Smaller change; job no longer hardcodes "bingx" or BingxClient.  
**Cons:** BingxClient file is still relatively large; validator/controller may still branch on provider type unless we add a “ping via factory” helper.

---

### C: Full multi-exchange layout (Bingx namespace)

- Put everything BingX under `Exchanges::Bingx`: `HttpClient`, `TradeNormalizer`, `TradeFetcher`, and a thin `BingxClient` that composes them. Same factory as in A for the job.
- Add a **provider registry** (e.g. `Exchanges::Providers.register("bingx", Exchanges::Bingx::Client)`) so the factory and validator resolve by `provider_type` only.

**Pros:** Clear namespace; scales to many exchanges.  
**Cons:** More structure than needed if only BingX is supported for a long time; some YAGNI.

---

## Key Decisions

| Area | Decision |
|------|----------|
| **Job** | Must not reference `"bingx"` or `Exchanges::BingxClient` directly. It should obtain a client (or “provider”) from the account and call `fetch_my_trades(since:)`. |
| **Provider abstraction** | A factory or registry that, given an `ExchangeAccount` (or provider_type + credentials), returns an object implementing the BaseProvider contract (`fetch_my_trades(since:)`). Ping for validation can be a class method on each client or a factory-driven “validate this account” call. |
| **BingxClient size** | Split into at least: (1) HTTP/signing layer, (2) normalizers. Orchestration can stay in one class that uses (1) and (2). |
| **Rails conventions** | Aim for smaller, single-responsibility classes under `app/services/exchanges/` (and optionally `exchanges/bingx/`). |

---

## Open Questions

1. **Multi-exchange timeline:** Is the goal to support a second exchange (e.g. Binance) soon, or mainly to clean up for conventions and future-proof the job? (Affects whether we do minimal factory (B) or full namespace + registry (A/C).)
2. **Validator / controller:** Should “ping” and “only BingX can sync” stay as provider-type branches, or should both go through the factory (e.g. “sync allowed if factory returns a client” and “validation = factory.client(account).ping” or equivalent)?
3. **Debug helpers:** Keep `debug_fetch_*` on BingxClient, or move to a console-only module to keep the main client slimmer?

---

## Resolved Questions

*(None yet.)*

---

## References

- Current client: `app/services/exchanges/bingx_client.rb`
- Job: `app/jobs/sync_exchange_account_job.rb`
- BaseProvider contract: `app/services/exchanges/base_provider.rb`
- Validator: `app/services/exchange_account_key_validator.rb`
- Dispatcher: `app/jobs/sync_dispatcher_job.rb`
- Controller sync action: `app/controllers/exchange_accounts_controller.rb#sync`
