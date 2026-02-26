---
shaping: true
---

# Multi-Exchange Automated Trade Logger (MVP) — Shaping

## Source

> Pitch: Multi-Exchange Automated Trade Logger (MVP)
>
> 1. Problem
> Manual trade journaling is a high-friction task that leads to data gaps and emotional bias. Traders need a "set and forget" system that centralizes their activity across multiple platforms without manual entry, ensuring 100% accuracy in performance tracking.
>
> 2. Appetite
> Small Batch (2-3 weeks). The focus is on a robust synchronization engine and a scalable data schema, rather than a polished UI.
>
> 3. Solution (The "Fat Marker" Sketch)
> We will build a Rails 8 application using a Service Provider Pattern to handle multiple exchanges.
> Exchange-Agnostic Core: The system must not care if a trade comes from Binance or BingX. We will use an abstract ExchangeProvider interface. Adding a new exchange should only require a new strategy class, not a database migration.
> Solid Queue Integration: Instead of Redis, we will use Solid Queue for background processing.
> Runtime Configurable Jobs: The sync frequency (Hourly, Daily, etc.) must be configurable at the User level. The system will dynamically schedule or throttle jobs based on individual user settings.
> The Sync Loop: Poll the exchange's "My Trades" endpoint. Filter for USDT/USDC pairs. Net Profit Calculation: (Price * Quantity) - Commission. Encryption: API Keys and Secrets must be encrypted using Rails' ActiveRecord::Encryption.
>
> 4. No-Gos (Boundaries)
> NO Redis: The stack must remain "Solid" (DB-backed).
> NO Historical Sync: Only fetch trades executed after the account is linked (Day 0 approach).
> NO Write Access: The application must strictly reject API keys with "Trade" or "Withdraw" permissions.
> NO Complex Pairs: Ignore non-stablecoin pairs (e.g., BTC/ETH) for now.
>
> 5. Data Schema & Architecture
> User → ExchangeAccount (provider_type, encrypted_credentials, sync_interval) → Trade (exchange_reference_id, symbol, side, raw_payload, fee, net_amount, executed_at). Provider: Exchanges::BinanceClient < BaseProvider, Exchanges::BingxClient < BaseProvider.
>
> 6. Rabbit Holes (Risks)
> Rate limiting; Solid Queue runtime scheduling for user-specific intervals; Binance vs BingX Trade vs Order history normalization.

---

## Requirements (R)

| ID | Requirement | Status |
|----|-------------|--------|
| R0 | Centralize trade activity across multiple exchanges without manual entry | Core goal |
| R1 | Accuracy of performance tracking (no data gaps from manual journaling) | Core goal |
| R2 | "Set and forget" — automated sync, no ongoing manual steps | Must-have |
| R3 | Support multiple exchanges; adding a new exchange = new strategy only, no DB migration | Must-have |
| R4 | Use Solid Queue (DB-backed jobs); no Redis | Must-have |
| R5 | Sync configurable per user (frequency and safety limits) | Must-have |
| R5.1 | Set of interval options (e.g. Hourly, Daily, Twice daily) in **user** configuration (one setting for all of a user's accounts), driving Solid Queue scheduling directly | Must-have |
| R5.2 | 🟡 Rate limit: at most N sync runs per account per day (e.g. twice) to respect exchange API limits | Must-have |
| R6 | Only fetch trades from link date forward (Day 0; no historical backfill) | Must-have |
| R7 | Reject API keys with Trade or Withdraw permissions (read-only) | Must-have |
| R8 | Only stablecoin pairs (e.g. USDT/USDC); ignore BTC/ETH etc. for MVP | Must-have |
| R9 | Encrypt API keys and secrets at rest (e.g. ActiveRecord::Encryption) | Must-have |

---

## A: Exchange-agnostic sync with provider pattern + Solid Queue

| Part | Mechanism | Flag |
|------|-----------|:----:|
| **A1** | Abstract ExchangeProvider; Binance/BingX clients implement it; Trade model stays unified | |
| **A2** | Solid Queue for background sync jobs (no Redis) | |
| **A3** | User configuration with a fixed set of interval options (Hourly, Daily, Twice daily); selection stored on User (one interval for all linked accounts); Solid Queue jobs scheduled/throttled directly from that setting | |
| **A4** | Sync loop: poll "My Trades", filter USDT/USDC, net = (Price × Qty) − Commission, store in Trade | |
| **A5** | Encrypted credentials on ExchangeAccount (ActiveRecord::Encryption) | |
| **A6** | Key validation: reject keys with Trade/Withdraw permissions before storing | |
| **A7** | Day 0: only fetch trades executed after account link (no historical sync) | |
| **A8** | 🟡 Rate limit: cap sync runs per ExchangeAccount (e.g. max 2/day); scheduler or job enqueue logic enforces before dispatching to avoid exchange API bans | |

---

## Fit Check: R × A

| Req | Requirement | Status | A |
|-----|-------------|--------|---|
| R0 | Centralize trade activity across multiple exchanges without manual entry | Core goal | ✅ |
| R1 | Accuracy of performance tracking (no data gaps from manual journaling) | Core goal | ✅ |
| R2 | "Set and forget" — automated sync, no ongoing manual steps | Must-have | ✅ |
| R3 | Support multiple exchanges; adding a new exchange = new strategy only, no DB migration | Must-have | ✅ |
| R4 | Use Solid Queue (DB-backed jobs); no Redis | Must-have | ✅ |
| R5 | Sync configurable per user (frequency and safety limits) | Must-have | ✅ |
| R5.1 | Set of interval options (e.g. Hourly, Daily, Twice daily) in user configuration (one for all accounts), driving Solid Queue scheduling directly | Must-have | ✅ |
| R5.2 | Rate limit: at most N sync runs per account per day (e.g. twice) to respect exchange API limits | Must-have | ✅ |
| R6 | Only fetch trades from link date forward (Day 0; no historical backfill) | Must-have | ✅ |
| R7 | Reject API keys with Trade or Withdraw permissions (read-only) | Must-have | ✅ |
| R8 | Only stablecoin pairs (e.g. USDT/USDC); ignore BTC/ETH etc. for MVP | Must-have | ✅ |
| R9 | Encrypt API keys and secrets at rest (e.g. ActiveRecord::Encryption) | Must-have | ✅ |

**Notes:**

- (None — R5/R5.1 covered by A3, R5.2 by A8.)

---

## Unsolved / Next steps

1. **Exchange API differences** — Binance vs BingX trade/order semantics are not yet explicit in R or shape parts; add if you want them in the fit check.
2. **Alternatives?** — If you want to compare approaches (e.g. different scheduling or rate-limit strategies), we can add Shape B and another column to the fit check.

---

You can **start from R** (tweak or add requirements, then check fit again) or **start from S** (detail A further, resolve A3, or add another shape). Which do you want to do next?
