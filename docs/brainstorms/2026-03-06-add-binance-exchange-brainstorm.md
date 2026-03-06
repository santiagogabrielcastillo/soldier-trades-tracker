# Add Binance (USDⓈ-M Futures) as Exchange — Brainstorm

**Date:** 2026-03-06  
**Scope:** Add Binance USDⓈ-M Futures as a second exchange provider so users can link a Binance Futures account and sync trades alongside BingX.  
**Reference:** [Binance USDⓈ-M Futures – General Info](https://developers.binance.com/docs/derivatives/usds-margined-futures/general-info)

---

## What We're Building

1. **Binance as a supported provider**  
   Users can create an exchange account with `provider_type: "binance"`, store API key/secret (read-only), and sync trades from Binance USDⓈ-M Futures into the same `trades` table and flows (dashboard, trades index, portfolios) as BingX.

2. **Same contract as BingX**  
   One client class implementing `Exchanges::BaseProvider` (e.g. `Exchanges::BinanceClient`): `#fetch_my_trades(since:)` returning normalized trade hashes; optional `self.ping(api_key:, api_secret:)` for key validation. Register in `Exchanges::ProviderForAccount::REGISTRY` so sync job, dispatcher, and validator work without further branching.

3. **API surface**  
   Binance Futures base URL: `https://fapi.binance.com` (testnet: `https://testnet.binancefuture.com`). Signed requests: HMAC SHA256, `X-MBX-APIKEY` header, `timestamp` and `signature` in query/body; same security model as in [General Info](https://developers.binance.com/docs/derivatives/usds-margined-futures/general-info).

4. **Trade source**  
   Primary source: `GET /fapi/v1/userTrades` (Account Trade List). Returns fills with `id`, `symbol`, `side`, `price`, `qty`, `commission`, `realizedPnl`, `time`, etc. Constraints: **symbol required**; **max 7-day window** per request; **past 6 months** only. **Strategy:** Call `GET /fapi/v2/positionRisk` (or equivalent) first to get symbols with activity; then for each symbol fetch userTrades in 7-day chunks from `since` up to now.

5. **Normalization**  
   Map Binance payloads to the same hash shape as BingX: `exchange_reference_id`, `symbol`, `side`, `price`, `quantity`, `fee_from_exchange` (or income-style `fee`, `net_amount`), `executed_at`, `raw_payload`, `position_id` (if available). **Symbol format:** Normalize Binance `BTCUSDT` to `BTC-USDT` on ingest so all code and UI see one format (no provider branching in PositionSummary or display).

6. **Current price for open positions**  
   Trades index uses current price for unrealized PnL. Today only BingX ticker is used. For Binance we need a Binance Futures mark price or ticker client (e.g. public endpoint) and plug it into the same flow (e.g. by provider in `Trades::IndexService` or a small ticker router).

---

## Why This Approach

- **Reuse existing abstraction:** `ProviderForAccount` + `BaseProvider` were designed for multiple providers. Adding Binance is a new client class + registry entry; sync job, validator, and dispatcher stay unchanged.
- **Single trades table:** Same schema and flows for all exchanges; `ExchangeAccount.provider_type` and `raw_payload` distinguish source; `PositionSummary` and UI already handle multiple accounts.
- **Read-only keys:** Enforce read-only API keys (Binance allows restricting keys); use a lightweight `ping` (e.g. one small signed request) so key validation works like BingX.

---

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Product scope | Binance USDⓈ-M Futures only (not Spot/COIN-M) | Matches your use case; keeps first implementation focused. |
| Trade source | `GET /fapi/v1/userTrades` (with multi-symbol + 7-day chunking strategy) | Official fill-level data; income endpoint is complementary. |
| Symbol discovery | Call account/position endpoint first (e.g. `GET /fapi/v2/positionRisk`), collect symbols with activity, then fetch userTrades per symbol in 7-day chunks | Avoids maintaining a symbol list; uses actual account activity. |
| Symbol format | Normalize to `BTC-USDT` on ingest (same as BingX) | Single format everywhere; PositionSummary and UI need no provider branching. |
| Ticker for unrealized PnL | Add Binance Futures mark/ticker fetcher and use when account is Binance | Same UX as BingX for open positions. |
| Key validation | Implement `BinanceClient.ping` (e.g. userTrades with limit=1 or account ping) | Aligns with existing read-only check and `ProviderForAccount.ping?`. |
| Testnet | Support testnet via configurable base URL (e.g. `https://testnet.binancefuture.com`) | Enables development and testing without production keys. |

---

## Open Questions

None that block implementation.

---

## Resolved Questions

- **Which Binance product?** → USDⓈ-M Futures only (fapi), as per your link.
- **Same sync flow as BingX?** → Yes; one client, same normalized hashes, same job and validator.
- **Symbol list for userTrades?** → Use position/account endpoint (e.g. `GET /fapi/v2/positionRisk`) to get symbols with activity, then query userTrades per symbol.
- **Symbol format?** → Normalize to `BTC-USDT` on ingest for consistency with BingX and existing code.
- **Testnet?** → Yes; support testnet base URL for development.

---

## Summary

Add a Binance USDⓈ-M Futures client that: discovers symbols via position/account endpoint; implements `fetch_my_trades(since:)` using `GET /fapi/v1/userTrades` per symbol in 7-day chunks; normalizes to existing trade hash shape with **symbol as `BTC-USDT`**; supports **testnet** via configurable base URL; registers in `ProviderForAccount`; implements `ping` for key validation; adds ticker/price support for unrealized PnL. Ready for `/plan`.
