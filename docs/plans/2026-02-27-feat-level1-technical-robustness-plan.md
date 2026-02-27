---
title: "feat: Level 1 Technical Robustness (uniqueness, API resilience, key validation, financial calculator)"
type: feat
status: active
date: 2026-02-27
---

# feat: Level 1 Technical Robustness

## Enhancement Summary

**Deepened on:** 2026-02-27  
**Sections enhanced:** 4 (uniqueness, API resilience, validation, financial calculator) + technical considerations  

### Key Improvements

1. **Uniqueness:** Use per-row rescue of `RecordNotUnique` (no transaction around the loop); avoid wrapping the entire sync in a transaction so one failed insert doesn’t abort the batch.
2. **ApiError:** Optional `retry_after` on the exception for 429 (Retry-After header); use Active Job `retry_on Exchanges::ApiError` with a wait strategy for clearer retry behavior.
3. **FinancialCalculator:** Use `BigDecimal` (e.g. `.to_d`) for all inputs and intermediate values to avoid float rounding errors; document precision/rounding (e.g. 8 decimal places to match `trades.fee` / `net_amount`).

### New Considerations Discovered

- **RecordNotUnique:** Rescuing inside a transaction can leave the transaction aborted (PostgreSQL). Our job does not wrap the trade loop in a transaction, so rescuing per `save!` and continuing is safe.
- **429 handling:** Custom exception can expose `retry_after` from the response header so retries align with the exchange’s rate limit.
- **Money precision:** Use BigDecimal throughout the calculator; match DB column scale (precision: 20, scale: 8) when rounding for storage.

---

## Overview

Four targeted improvements to the multi-exchange trade tracker: enforce trade uniqueness at the DB level, make BingX API errors retriable by Solid Queue, ensure API key validation runs on account creation, and centralize financial math (net_amount, fee) in one exchange-agnostic place.

**Context:** [Brainstorm 2026-02-26](../brainstorms/2026-02-26-level1-technical-robustness-brainstorm.md). Approach: minimal change (recommended); raw hash passes only `price` and `quantity`; validation uses current ping.

## Problem Statement / Motivation

- **Duplicates on retry:** Sync job uses `find_or_initialize_by`; a DB unique constraint guarantees no duplicates if the job is retried or run concurrently.
- **Sync failures not retriable:** BingX client raises generic strings or `JSON::ParserError`; Solid Queue has no standard exception to retry on for 5xx/429/timeouts.
- **Key verification on create:** Users should not save an exchange account until the key is verified with a light request; today validation exists on the model but error messages can be clearer.
- **Exchange-specific math:** Net amount and fee are computed inside BingxClient with BingX-specific sign logic; adding another exchange would duplicate conventions. Centralizing in one calculator keeps sign rules and formula consistent.

## Proposed Solution

### 1. Database-level uniqueness

- **Confirm** the unique index on `trades(exchange_account_id, exchange_reference_id)` exists (`db/schema.rb` and migration `create_trades`). No new migration unless the target branch is missing it.
- **Concurrent sync:** If two jobs sync the same account, `save!` can raise `ActiveRecord::RecordNotUnique`. Decide: rescue and skip the duplicate row (log and continue), or let the job fail and retry. Recommendation: rescue, log, and continue so one successful run wins.

**Files:** `db/schema.rb` (verify), optionally `app/jobs/sync_exchange_account_job.rb` (rescue `RecordNotUnique`).

#### Research Insights (Uniqueness)

- **Best practice:** Do not wrap the sync loop in a transaction. If you rescue `RecordNotUnique` inside a transaction, PostgreSQL marks the transaction aborted and subsequent statements fail. Our job does one `save!` per trade with no outer transaction, so rescuing per row and continuing is safe ([Handling unique constraint exceptions inside transaction](https://stackoverflow.com/questions/51035129/handling-unique-constraint-exceptions-inside-transaction)).
- **Implementation:** In the job, around `trade.save!` rescue `ActiveRecord::RecordNotUnique`, log (e.g. exchange_reference_id), and continue to the next trade so one duplicate does not fail the whole run.
- **Edge case:** Two concurrent jobs for the same account may both try to create the same trade; the unique index ensures one insert wins and the other gets `RecordNotUnique`; rescuing and skipping is idempotent.

### 2. API resilience and retriable errors

- **Introduce** `Exchanges::ApiError` (subclass of `StandardError`). Use it as the single exception type that means “retry later.”
- **In `Exchanges::BingxClient#signed_get` (and call paths):**
  - For HTTP **429** or **5xx:** raise `Exchanges::ApiError` with message including code/body (do not raise for other 4xx).
  - For **timeouts:** rescue `Net::OpenTimeout`, `Net::ReadTimeout` (or `Timeout::Error`), wrap in `Exchanges::ApiError`, re-raise.
  - For **JSON parse errors:** rescue `JSON::ParserError`, wrap in `Exchanges::ApiError`, re-raise.
  - For **200 with empty/non-JSON body:** treat as API error and raise `Exchanges::ApiError` (do not return nil silently).
- **Job:** Keep current `rescue => e; log; raise` so Solid Queue retries on any unhandled exception. No need to rescue only `ApiError` unless we want to avoid retrying other errors (e.g. `ArgumentError`); for now, retrying on all exceptions is acceptable, or document “retriable: Exchanges::ApiError only” and rescue others to not retry.

**Files:** `app/services/exchanges/api_error.rb` (new), `app/services/exchanges/bingx_client.rb` (`signed_get` and any caller that parses JSON).

#### Research Insights (API resilience)

- **Best practice:** Rescue `Net::OpenTimeout` and `Net::ReadTimeout` explicitly (or `Timeout::Error` if you want a single rescue). For JSON, rescue `JSON::ParserError` and re-raise as your retriable type so the job gets one consistent exception ([Rescuing Net::HTTP timeout](https://stackoverflow.com/questions/32912397/rescuing-a-nethttp-timeout-testing-with-rspec), [JSON parse errors](https://stackoverflow.com/questions/27944050/how-to-handle-json-parser-errors-in-ruby)).
- **Solid Queue / Active Job:** Use `retry_on Exchanges::ApiError` in the job (with optional `wait:` or `wait: :exponentially_longer`) so only retriable errors are retried. Custom exception can expose `retry_after` for 429 so the job can honor `Retry-After` ([Rails retry_on](https://codewithrails.com/blog/rails-smart-retry-strategies/), [Solid Queue](https://alybadawy.com/blog/post/solid-queue-advanced)).
- **Implementation:** In `signed_get`, parse response after checking status. For 200, if `body.blank?` or `JSON.parse` raises, raise `Exchanges::ApiError`. Do not rescue generic `Exception`; limit to the known retriable cases.
- **Edge case:** 200 with empty body: treat as API error (raise ApiError) rather than returning nil and letting callers fail later.

### 3. Validation on creation

- **Confirm** that creating an `ExchangeAccount` already runs `validate :read_only_api_key`, which calls `ExchangeAccountKeyValidator.read_only?(provider_type, api_key, api_secret)` (BingX ping). No controller change required for “validate before save.”
- **Improve UX:** When the validator returns false, the model currently adds “API key must be read-only…”. If the failure was due to ping (invalid key, network, 429), consider a clearer message, e.g. “Could not verify API key. Check key, secret, and network.” Optionally distinguish “could not verify” vs “verified but not read-only” if the validator can expose that (e.g. ping raises vs returns false after successful ping with wrong permissions).
- **Document:** Only BingX keys are verified via ping; other provider types (e.g. binance) currently skip real verification until implemented.

**Files:** `app/models/exchange_account.rb`, `app/services/exchange_account_key_validator.rb` (optional: return symbol or struct for failure reason), `app/controllers/exchange_accounts_controller.rb` (only if we add custom error message from validator).

#### Research Insights (Validation)

- **Current behavior:** Validation already runs on `save` via `validate :read_only_api_key`. No need to duplicate the call in the controller; ensure the create flow always calls `save` (or `save!`) so validation runs.
- **UX:** If the validator can distinguish “ping failed” (exception or connection error) from “ping succeeded but key has trade/withdraw permissions,” return a symbol or small struct and map to two messages: “Could not verify API key. Check key, secret, and network.” vs “API key must be read-only.”
- **Documentation:** In the validator or model, document that only BingX performs a real ping; other providers return true until implemented.

### 4. Response-agnostic financial logic

- **Add** a central calculator (e.g. `app/services/exchanges/financial_calculator.rb` or `Exchanges::FinancialCalculator`) with a single entry point that takes **price, quantity, side, fee_from_exchange** (optional, default 0) and returns **fee** and **net_amount** with a documented sign convention:
  - **Sign convention (to document in code and plan):** e.g. fee as non-positive (cost); net_amount: positive = inflow (e.g. sell proceeds), negative = outflow (e.g. buy cost). Align with current BingX behavior so existing data remains consistent.
- **Formula:** notional = price * quantity; net_amount = side == "sell" ? notional - fee : -notional - fee; fee stored as provided (e.g. negative commission). Handle nil/zero: treat nil as 0 for fee_from_exchange; require price and quantity present (or treat 0 as 0 and allow).
- **Income-style records:** `normalize_income_to_trade` has no price/qty, only `amount`. Options: (a) calculator has a second method or optional params for “amount-only” (e.g. `compute_from_amount(amount, fee_from_exchange: 0)` → fee + net_amount), or (b) keep income path setting `net_amount = amount`, `fee = 0` in the client and do not run through the calculator. Recommendation: (b) for now; income is exchange-specific and already correct; only “trade” legs use the calculator.
- **BingxClient refactor:** The three normalizers (`normalize_v1_order_to_trade`, `normalize_fill_to_trade`, `normalize_income_to_trade`) should return a **raw normalized hash** (exchange_reference_id, symbol, side, executed_at, raw_payload, and **price, quantity, fee_from_exchange**). Do **not** compute net_amount or fee in the client for trade-style records.
- **Job or BaseProvider:** After fetching trades, for each hash that has price/quantity, call the calculator and set `fee` and `net_amount` on the attribute hash before `assign_attributes`. For income-style hashes (no price/quantity), keep current behavior (client sends fee and net_amount).
- **BaseProvider contract:** Document that subclasses may return “trade” hashes (price, quantity, side, fee_from_exchange) or “income” hashes (amount, fee); the job (or a shared layer) applies the calculator to trade hashes and passes through income hashes.

**Files:** `app/services/exchanges/financial_calculator.rb` (new), `app/services/exchanges/bingx_client.rb` (normalizers return raw hash; remove net_amount/fee computation for trades), `app/services/exchanges/base_provider.rb` (optional: document contract), `app/jobs/sync_exchange_account_job.rb` (call calculator when building trade attributes).

#### Research Insights (Financial calculator)

- **Precision:** Use `BigDecimal` for all inputs and intermediates. Ruby floats cause rounding errors (e.g. `(1.2 - 1.0) == 0.2` is false). Coerce with `.to_d` and round final values to match DB columns (precision: 20, scale: 8) ([BigDecimal](https://ruby-doc.org/stdlib-3.1.0/libdoc/bigdecimal/rdoc/BigDecimal.html), [Currency in Ruby](https://honeybadger.io/blog/ruby-currency)).
- **Implementation:** In the calculator, accept `price`, `quantity`, `side`, `fee_from_exchange`; compute `notional = price.to_d * quantity.to_d`; apply the same formula as current BingX (`side == "sell" ? notional - fee : -notional - fee`); store fee as the exchange value (typically negative). Round with `.round(8)` before returning if you need to match column scale.
- **Edge case:** Nil or blank `fee_from_exchange` → treat as 0. Zero price or quantity → notional 0; net_amount becomes `-fee` or `0 - fee`; document that zero-quantity trades are allowed for consistency.
- **Income path:** Keep income records out of the calculator; they have no price/qty and are already correct in the client.

## Technical Considerations

- **Rails 8 / ActiveRecord::Encryption:** No change to encryption; existing `encrypts :api_key` and `:api_secret` remain. Validator and controller already use decrypted values.
- **Solid Queue:** Retries on unhandled exceptions. Using `Exchanges::ApiError` allows optional “retry only on ApiError” in the job later without changing the client.
- **Backward compatibility:** Calculator output must match current BingX net_amount/fee for existing syncs (same formula and sign). No data migration.

#### Research Insights (Technical)

- **Job retries:** Prefer `retry_on Exchanges::ApiError` in the job so only retriable errors trigger retries; other exceptions (e.g. `ArgumentError`, validation) can be handled with `discard_on` or no retry ([Solid Queue](https://alybadawy.com/blog/post/solid-queue-advanced)).
- **ApiError payload:** Consider storing `response_code` and optional `retry_after` on the exception so the job or retry logic can use them (e.g. exponential backoff vs fixed delay from header).

## Acceptance Criteria

- [x] **Uniqueness:** Unique index on `trades(exchange_account_id, exchange_reference_id)` confirmed (or migration added if missing). If concurrent sync is supported, duplicate key is rescued and logged; job continues.
- [x] **ApiError:** `Exchanges::ApiError` exists. BingxClient raises it for 429, 5xx, timeouts, and JSON/empty-body errors; does not raise it for 4xx (other than 429).
- [x] **Validation:** New exchange account create still runs key validation (existing model validation). Error message is clear when key cannot be verified (e.g. network/invalid key). Document that only BingX is verified via ping.
- [x] **FinancialCalculator:** New service with documented sign convention; takes price, quantity, side, fee_from_exchange; returns fee and net_amount. Used for all trade-style records from BingxClient; income-style records unchanged.
- [x] **BingxClient:** Trade normalizers return raw hash (price, quantity, side, fee_from_exchange, …) without computing net_amount/fee. Job (or shared layer) calls calculator and assigns fee and net_amount before saving trades.
- [x] **Tests:** Unit tests for FinancialCalculator (sign convention, edge cases); tests for BingxClient raising ApiError on 429/5xx/timeout/parse; sync job still creates/updates trades correctly with calculator in the loop.

## Success Metrics

- Sync job never inserts duplicate trades (DB enforces; job handles race if implemented).
- Transient exchange/network failures (5xx, 429, timeout) cause job to retry via Solid Queue without code changes.
- New exchange integrations only need to produce raw hashes; fee/net_amount logic lives in one place.

## Dependencies & Risks

- **Income vs trade:** If future exchanges send “income” style with only amount, keep a separate path (no calculator) to avoid overloading the calculator API.
- **Validation UX:** Improving “could not verify” vs “not read-only” may require the validator to distinguish failure reasons (e.g. exception vs false), which could mean small API change in `ExchangeAccountKeyValidator`.

## References & Research

- Brainstorm: [2026-02-26-level1-technical-robustness-brainstorm.md](../brainstorms/2026-02-26-level1-technical-robustness-brainstorm.md)
- Current unique index: `db/schema.rb` (index_trades_on_account_and_reference)
- Client HTTP/JSON: `app/services/exchanges/bingx_client.rb` (`signed_get`, normalizers)
- Key validation: `app/models/exchange_account.rb` (`read_only_api_key`), `app/services/exchange_account_key_validator.rb`
- Sync job: `app/jobs/sync_exchange_account_job.rb`

### Deepen-plan references

- [Handling unique constraint exceptions inside transaction](https://stackoverflow.com/questions/51035129/handling-unique-constraint-exceptions-inside-transaction)
- [Rescuing Net::HTTP timeout](https://stackoverflow.com/questions/32912397/rescuing-a-nethttp-timeout-testing-with-rspec), [JSON parse errors in Ruby](https://stackoverflow.com/questions/27944050/how-to-handle-json-parser-errors-in-ruby)
- [Rails retry_on and error-aware delays](https://codewithrails.com/blog/rails-smart-retry-strategies/), [Solid Queue advanced](https://alybadawy.com/blog/post/solid-queue-advanced)
- [Ruby BigDecimal](https://ruby-doc.org/stdlib-3.1.0/libdoc/bigdecimal/rdoc/BigDecimal.html), [Currency calculations in Ruby](https://honeybadger.io/blog/ruby-currency)
