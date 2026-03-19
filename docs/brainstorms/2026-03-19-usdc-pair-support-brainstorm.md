# USDC Pair Support & Per-Account Quote Currency Whitelist

**Date:** 2026-03-19
**Status:** Brainstorm complete

---

## What We're Building

Binance USDC futures trades are currently not being synced. We're fixing that bug and adding a per-account configurable quote currency whitelist so users can control which quote currencies are synced (defaulting to USDT + USDC).

## Problem Statement

- **Binance:** No symbol filtering exists — USDC trades _should_ flow through, but they aren't. Root cause suspected in symbol discovery (`positionRisk` / `income` endpoints). Needs investigation.
- **BingX:** Already has `STABLEQUOTE_SYMBOLS = %w[USDT USDC].freeze` hardcoded — USDC already supported, no bug here.
- **Gap:** No per-account configuration for which quote currencies to allow; `ExchangeAccount` has no settings column.

## Why This Approach

**`settings` JSONB column on `ExchangeAccount`** — chosen over `UserPreference` because quote currency configuration is intrinsic to the exchange account, not a UI display preference. It survives preference resets, is scoped correctly to the account, and sets up a clean `settings` home for future per-account config.

`store_accessor` on a JSONB column is idiomatic Rails and requires minimal boilerplate.

## Key Decisions

1. **Storage:** Add `settings jsonb, default: {}` column to `exchange_accounts`. Use `store_accessor :settings, :allowed_quote_currencies` on the model.
2. **Default:** `%w[USDT USDC]` — both stablecoins enabled out of the box for all accounts (new and existing via migration default + model initializer).
3. **Filtering location:** Inside each exchange client, after normalization — mirrors the existing BingX `stablequote_pair?` pattern. The client receives `allowed_quote_currencies` from the account settings.
4. **BingX refactor:** Remove hardcoded `STABLEQUOTE_SYMBOLS` constant from `BingxClient`; replace with the account setting. BingX behavior is unchanged by default.
5. **Binance investigation:** Before wiring in the filter, debug _why_ USDC trades aren't discovered. Check `positionRisk` and `income` endpoint responses for USDC symbols. The normalizer already handles USDC formatting (`BTCUSDC` → `BTC-USDC`).
6. **UI for settings:** Out of scope for now — configure via Rails console / future account settings page.

## Scope

### In scope
- Migration: add `settings` JSONB column to `exchange_accounts`
- `ExchangeAccount` model: `store_accessor`, default initializer, validation (array of valid quote currencies)
- `BinanceClient`: debug symbol discovery for USDC + add `allowed_quote?` guard after normalization
- `BingxClient`: replace `STABLEQUOTE_SYMBOLS` constant with account setting
- `ProviderForAccount` / client constructors: pass `allowed_quote_currencies` into clients
- Tests: unit tests for `allowed_quote?` helper, integration test for USDC trade persistence

### Out of scope
- UI for editing allowed quote currencies per account
- Support for non-stablecoin quote currencies (BTC-margined contracts)
- BingX USDC-specific investigation (already supported)

## Open Questions

_None — all resolved in brainstorm session._

## Resolved Questions

- **Per-account vs global?** → Per account. Different accounts might trade different quote currencies.
- **Quote currency vs full symbol pairs?** → Quote currency only. Simpler to configure; can expand to full pair granularity later.
- **UserPreference vs settings column?** → Settings column — intrinsic account config, not UI preference state.
- **BingX broken?** → No, already has USDC in its whitelist. Only Binance is affected.
