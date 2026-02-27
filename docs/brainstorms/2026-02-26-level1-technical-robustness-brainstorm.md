# Brainstorm: Level 1 Technical Robustness

**Date:** 2026-02-26

## What We're Building

Four improvements to the multi-exchange trade tracker (Rails 8, Solid Queue, PostgreSQL):

1. **Database-level uniqueness** for trades to prevent duplicates on job retries.
2. **API resilience** in `Exchanges::BingxClient`: timeouts, JSON errors, and 5xx/429 mapped to retriable exceptions for Solid Queue.
3. **Validation on creation** of `ExchangeAccount`: verify API keys with a light request before saving.
4. **Response-agnostic financial logic**: centralize `net_amount` and fee sign conventions so exchange-specific APIs feed a normalized shape and one place does the math.

---

## Current State (from repo)

- **Trades uniqueness:** `db/schema.rb` already has a unique composite index on `trades(exchange_account_id, exchange_reference_id)`. The create migration added it. No migration change needed unless the index was removed elsewhere.
- **BingxClient:** Uses `Net::HTTP` with `open_timeout: 10`, `read_timeout: 15`. On non-200 it raises a generic `"BingX API error ..."`; on `JSON::ParserError` it re-raises with a message. No distinction for 429 or 5xx, and no retriable exception type.
- **Key validation:** `ExchangeAccountKeyValidator.read_only?` exists and uses `BingxClient.ping` (one fill request). It is **not** called in `ExchangeAccountsController#create`; accounts are saved without verifying the key.
- **Financial math:** `BingxClient` computes `net_amount` and `fee` in three normalizers (`normalize_v1_order_to_trade`, `normalize_fill_to_trade`, `normalize_income_to_trade`) with BingX-specific logic (e.g. `side == "sell" ? notional - commission : -notional - commission`). `BaseProvider` only documents the required hash keys; it does not perform calculations.

---

## Why This Approach

- **Uniqueness:** Rely on the existing index; add a migration only if the project’s schema no longer has it (e.g. different branch). Job already uses `find_or_initialize_by(exchange_reference_id)` so duplicates are avoided at read time; the index enforces at write time and survives retries.
- **API resilience:** Solid Queue retries on unhandled exceptions. By raising a single, well-known exception type (e.g. `Exchanges::ApiError`) for 5xx and 429, and rescuing `JSON::ParserError` / `Timeout::Error` and re-raising as that same type, we get consistent retry behavior without coupling to BingX in the job.
- **Validation on creation:** Call the existing validator before `save` in the controller (or in a service used by the controller). Use the current “ping” (light read) unless we explicitly want a different “light” request (e.g. balance); that can be a small open point.
- **Centralized financial logic:** Clients return a **raw normalized hash** (exchange-agnostic fields: e.g. price, quantity, side, fee_from_exchange, and/or notional). A shared **FinancialCalculator** (or concern) computes `net_amount` and normalized `fee` with a single sign convention (e.g. negative = outflow). New exchanges then only map API → raw hash; they don’t implement money math.

---

## Key Decisions

| Area | Decision |
|------|----------|
| **Trades uniqueness** | Keep existing unique index; add migration only if missing in target branch. |
| **Retriable errors** | Map 5xx and 429 (and optionally timeouts/JSON) to one exception type (e.g. `Exchanges::ApiError`) so the job can retry without special-case logic. |
| **Key validation** | Run `ExchangeAccountKeyValidator` before saving a new `ExchangeAccount`; fail create with a clear message if validation fails. |
| **Raw normalized hash** | Clients produce a hash with fields needed for central calculation (e.g. price, quantity, side, fee_from_exchange, symbol, timestamps, raw_payload). Fee can be optional if the exchange doesn’t report it. |
| **FinancialCalculator** | Single place that takes the raw normalized hash (or a subset) and returns `fee` and `net_amount` with consistent sign (e.g. fee as negative cost, net_amount positive = inflow). |
| **BaseProvider / job** | BaseProvider (or the job) accepts the raw hash from the client, runs it through FinancialCalculator, then builds the attribute hash for `Trade` (including `fee`, `net_amount`). |

---

## Approaches Considered

### A: Minimal change (recommended)

- **Uniqueness:** Confirm index in schema; no migration unless absent.
- **Resilience:** In BingxClient, rescue `Timeout::Error`, `JSON::ParserError`, and non-200 responses; for 429 and 5xx (and optionally timeout/parse), raise `Exchanges::ApiError`. Job keeps a single `rescue` that re-raises so Solid Queue retries.
- **Validation:** In controller (or a small service), before `save`, call `ExchangeAccountKeyValidator.read_only?(provider_type, api_key, api_secret)`; if false, add error and re-render new.
- **Financial:** Introduce a `FinancialCalculator` (or `Exchanges::FinancialCalculator`) with one method, e.g. `compute(price:, quantity:, side:, fee_from_exchange: 0)` → `{ fee:, net_amount: }`. BingxClient normalizers return a raw hash (price, qty, side, fee_from_exchange, symbol, executed_at, raw_payload, exchange_reference_id); the job (or BaseProvider) calls the calculator and assigns `fee` and `net_amount` when building the trade.

**Pros:** Small, clear boundaries; one place for sign conventions; easy to add more exchanges.  
**Cons:** One extra step (calculator) in the pipeline.

### B: BaseProvider owns the pipeline

- Same as A, but BaseProvider defines the contract: subclasses return an array of “raw normalized” hashes; BaseProvider (or a shared method) runs each through FinancialCalculator and returns the final hashes for the job. Job only sees fully computed attributes.

**Pros:** Job and clients are fully decoupled from calculation.  
**Cons:** Slightly more indirection; BaseProvider grows.

### C: No central calculator; document convention only

- Keep calculation in each client but document sign convention and formula in BaseProvider; add shared tests that each client’s output satisfies the convention.

**Pros:** No new service.  
**Cons:** Sign logic stays duplicated; easy for a new exchange to diverge.

---

## Open Questions

(None.)

---

## Resolved Questions

1. **Raw hash shape:** Clients pass only `price` and `quantity`; the central calculator computes notional and then net_amount so one place owns the formula.
2. **Validation "light" request:** Keep using the current ping (one fill/order request) for key validation.

---

## Next Steps

- Resolve open questions above.
- Then: implement migration (if needed), BingxClient error handling, controller validation, FinancialCalculator, and client refactor to raw hash + calculator in the job or BaseProvider.
