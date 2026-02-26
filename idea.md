Pitch: Multi-Exchange Automated Trade Logger (MVP)
1. Problem
Manual trade journaling is a high-friction task that leads to data gaps and emotional bias. Traders need a "set and forget" system that centralizes their activity across multiple platforms without manual entry, ensuring 100% accuracy in performance tracking.

2. Appetite
Small Batch (2-3 weeks). The focus is on a robust synchronization engine and a scalable data schema, rather than a polished UI.

3. Solution (The "Fat Marker" Sketch)
We will build a Rails 8 application using a Service Provider Pattern to handle multiple exchanges.

Exchange-Agnostic Core: The system must not care if a trade comes from Binance or BingX. We will use an abstract ExchangeProvider interface. Adding a new exchange should only require a new strategy class, not a database migration.

Solid Queue Integration: Instead of Redis, we will use Solid Queue for background processing.

Runtime Configurable Jobs: Unlike static recurring.yml files, the sync frequency (Hourly, Daily, etc.) must be configurable at the User level. The system will dynamically schedule or throttle jobs based on individual user settings.

The Sync Loop:

Poll the exchange's "My Trades" endpoint.

Filter for USDT/USDC pairs.

Net Profit Calculation: Explicitly calculate (Price * Quantity) - Commission.

Encryption: API Keys and Secrets must be encrypted using Rails' ActiveRecord::Encryption.

4. No-Gos (Boundaries)
NO Redis: The stack must remain "Solid" (DB-backed).

NO Historical Sync: To keep the MVP within scope, we only fetch trades executed after the account is linked (Day 0 approach).

NO Write Access: The application must strictly reject API keys with "Trade" or "Withdraw" permissions.

NO Complex Pairs: Ignore non-stablecoin pairs (e.g., BTC/ETH cross-rates) for now.

5. Data Schema & Architecture
User: Owns multiple ExchangeAccounts.

ExchangeAccount: Stores provider_type (e.g., "Binance"), encrypted_credentials, and sync_interval (user-defined).

Trade: A unified table for all platforms: exchange_reference_id, symbol, side, raw_payload, fee, net_amount, executed_at.

Provider Pattern:

Exchanges::BinanceClient < BaseProvider

Exchanges::BingxClient < BaseProvider

6. Rabbit Holes (Risks)
Rate Limiting: Each user-configured cron job must respect the exchange's API weight limits to avoid IP bans.

Solid Queue Runtime Scheduling: Since recurring.yml is usually static, we need a clean way to handle user-specific intervals (e.g., a "Manager" job that spawns individual sync tasks).

Confidence Level: 0.95
Key Caveats: BingX and Binance have different "Trade History" vs "Order History" logic; the abstraction layer (Provider) must normalize these differences so the Trade model remains consistent.