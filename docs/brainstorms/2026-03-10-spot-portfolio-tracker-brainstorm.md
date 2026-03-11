# Spot Portfolio Tracker — Brainstorm

**Date:** 2026-03-10  
**Scope:** Add a Spot Portfolio Tracker module: CSV-only input, true breakeven/cost basis, realized vs unrealized PnL, position epochs. Same app and users as existing futures tracker; no exchange connection for spot. Idempotent uploads and clear separation from futures while staying DRY.

---

## What We're Building

1. **Spot portfolio state from CSV** — Parse a transaction-history CSV (e.g. `Portfolio_with_transaction_history.csv`), store transactions without duplicating rows on re-upload (content-based deduplication).
2. **Per-token truth** — Current balance, net USD invested (risk), true breakeven price, realized PnL, unrealized PnL (with current price).
3. **Position lifecycle** — When a token balance hits zero, the position is closed. A later buy is a new "epoch" (new cost basis), not blended with closed history.
4. **Same app, same users** — Spot lives alongside the existing futures tracker; futures and spot are clearly separated in data and UI but share User, auth, and patterns (DRY).

---

## CSV Format (Reference)

Source: CSV with columns as in the user's file (e.g. `Portfolio_with_transaction_history.csv`).

| Column            | Example           | Notes |
|-------------------|-------------------|--------|
| Date (UTC-3:00)   | 2026-01-19 10:40:00 | Quoted; parse to `executed_at` (store in UTC or with timezone). |
| Token             | LDO, AVAX, LINK   | Symbol/ticker. |
| Type              | buy, sell         | Normalize to downcase. |
| Price (USD)       | 0.5454            | Decimal. |
| Amount            | 1,150.01 or 33.70 | May contain comma as thousands separator; normalize before math and dedup. |
| Total value (USD) | 627.22            | Decimal; can be derived as Price × Amount but useful for validation. |
| Fee               | -- or number      | "--" when no fee; parse to numeric or null. |
| Fee Currency      | (empty or e.g. BNB) | For future: fees in non-USD. |
| Notes             | (optional)        | Free text. |

- **File order:** Rows may be newest-first; processing must sort by date ascending per token for correct balance and epoch logic.
- **Deduplication key:** Content-based. Normalize: date (e.g. ISO), token (trimmed/upcased), type, price (canonical decimal), amount (strip commas, canonical decimal). Use a **row signature** (e.g. SHA256 of normalized string or composite unique index) so the same logical row in a re-upload does not create a duplicate.

---

## Why This Approach

- **Separate spot tables** — Spot has its own transaction and position-epoch tables; futures keep using `trades`, `positions`, `exchange_accounts`. This avoids overloading existing schema with nullable spot-only columns and keeps futures logic untouched.
- **No exchange link for spot** — Spot data is scoped to the user (and optionally a "spot portfolio" or "spot account" entity). No `exchange_account_id` for spot transactions; CSV is the only source.
- **Content-based idempotency** — No external ID in the CSV; we derive a unique row signature from normalized fields so uploading the same CSV twice does not duplicate positions/transactions.
- **DRY** — Same `User`; shared layout, auth, and navigation (e.g. tabs: Futures | Spot); shared decimal/date helpers and patterns (scopes, presenters) where it makes sense. Domain logic (breakeven, cost basis, FIFO/LIFO/WAC) lives in spot-specific services/models.

---

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Spot vs futures storage | Separate tables for spot (e.g. `spot_transactions`, `spot_position_epochs`) | Clear separation; futures schema stays focused; no polymorphic mess. |
| Deduplication | Content-based row signature (normalized date, token, type, price, amount) | User confirmed; no ID column in CSV. Re-upload = skip or update existing row. |
| Ownership | Spot data tied to `User` (and optionally a spot "portfolio" or "account") | Same app, same users; no exchange account for spot. |
| Position lifecycle | Balance = 0 → position closed; next buy = new epoch | Per user spec; breakeven and cost basis reset for the new epoch. |
| Cost basis / realized PnL | Recommend **FIFO** for spot (or make configurable later) | FIFO is common for crypto and tax; simple to explain. WAC is simpler to compute but less precise per lot. LIFO possible later if needed. |
| Current price (unrealized PnL) | Connected exchange's **public spot ticker** (no auth) | Reuse CurrentDataFetcher + per-provider TickerFetcher pattern; add spot symbol + spot API path. User must have ≥1 connected exchange. |
| Fees (MVP) | **Discard** | Do not use in net USD or PnL; can add fee columns for display later. |
| Spot accounts | One per user for start; **schema ready for multiple** | `spot_accounts` table from day one; `spot_transactions.spot_account_id`; MVP = one default spot_account per user. |

---

## Database Schema (Proposed)

- **`spot_accounts`** — One per user for MVP; later multiple per user (e.g. "Binance Spot CSV", "Kraken Spot").
  - `user_id` (FK), `name` (e.g. "Default"), `default` (boolean), timestamps. MVP: create one default spot_account per user when they first use spot.
- **`spot_transactions`** — One row per CSV row (after dedup).
  - `spot_account_id` (FK), `executed_at`, `token` (string), `side` (buy/sell), `price_usd`, `amount`, `total_value_usd`, `notes`, `row_signature` (unique per spot account, for idempotency), timestamps.
  - **MVP: no fee columns** in calculations; fee/fee_currency can be added later for display only. Unique constraint on `(spot_account_id, row_signature)`.
- **`spot_position_epochs`** (or computed on the fly) — One "open then possibly closed" period per token per spot account.
  - If stored: `spot_account_id`, `token`, `opened_at`, `closed_at` (null if open), `net_usd_invested`, `quantity`, `realized_pnl`, etc. No `exchange_account_id`; spot is scoped by `spot_account`.

Futures tables (`trades`, `positions`, `position_trades`, `exchange_accounts`) remain unchanged and are used only for API-synced futures data.

---

## Core Logic (Algorithm Sketch)

1. **Import CSV** — Parse rows; normalize date, token, type, price, amount (strip commas), fee; compute `row_signature` (e.g. digest of normalized fields). For each row: if `(user_id, row_signature)` exists, skip (or update); else insert `spot_transactions` row.
2. **Per-token state** — For each token, load `spot_transactions` ordered by `executed_at` ASC.
3. **Running balance and epochs** — Initialize balance = 0, epoch = 0. For each tx: if buy then balance += amount; if sell then balance -= amount. If balance hits 0 after a sell, close current epoch; next buy starts epoch + 1.
4. **Net USD and breakeven** — Within current epoch: net_usd += (buy total_value - sell total_value). **MVP: discard fees** (do not subtract from net USD or PnL). True breakeven = net_usd / balance when balance > 0. If net_usd &lt; 0 (house money), treat as zero cost or flag as "risk-free" for display.
5. **Realized PnL** — On each sell, match sold quantity to lots (FIFO: oldest buys first). Realized PnL = sum(sold_qty × (sell_price - buy_price)) per matched lot; accumulate per epoch and overall.
6. **Unrealized PnL** — For open epoch: (current_price - breakeven) × balance. **Current price:** use a connected exchange's **public spot ticker endpoint** (no auth). Reuse the app pattern: `Positions::CurrentDataFetcher` + per-provider ticker fetchers; add spot symbol format (e.g. LDOUSDT) and spot API path (e.g. Binance/BingX spot ticker). User must have at least one connected exchange; pick one (e.g. default or first) to fetch spot prices for tokens in their spot portfolio.

---

## Edge Cases

| Case | Handling |
|------|----------|
| **Fee = "--"** | Parse as null; **MVP: discard fees** (no fee columns in calculations). |
| **Amount with comma** | Normalize to decimal (strip commas) for storage and signature. |
| **Fee in BNB (or other currency)** | **MVP: ignore.** Can add fee/fee_currency columns for display later. |
| **Airdrops / transfers in or out** | No USD price in CSV; could add Type = "transfer_in" / "transfer_out" with optional price or leave for later. |
| **Same timestamp + token + type** (e.g. two sells same minute) | Include price and amount in signature so two distinct rows are not collapsed; if truly duplicate, same signature → skip. |
| **Re-upload with corrected row** | Content change → new signature → new row. Consider optional "replace by same (date, token, type)" policy later if user wants to fix typos. |

---

## Futures vs Spot Separation (DRY)

- **Data:** Futures: `ExchangeAccount` → `Trade` → `Position`. Spot: `User` → `SpotTransaction` (no exchange). No shared table that mixes the two.
- **UI:** Same nav and layout; separate tabs or sections (e.g. "Futures" vs "Spot"). Shared: user menu, preferences pattern, date filters, decimal/currency formatting.
- **Code:** Shared concerns: `User`, authentication, authorization (e.g. "my data only"). Spot-specific: CSV parser, row signature, breakeven/epoch/FIFO logic. Reuse helpers (decimal rounding, date ranges) and avoid copy-paste; keep domain logic in dedicated services (e.g. `Spot::ImportFromCsvService`, `Spot::PositionStateService`).

---

## Open Questions

_None; resolved below._

---

## Resolved Questions

- **Relation to app:** Same app, same users; spot is a new area; no exchange connection for spot (CSV only).
- **Deduplication:** Content-based (normalized date, token, type, price, amount) → row signature; no duplicate rows on re-upload.
- **Futures vs spot:** Separate tables and domain logic; DRY via shared User, auth, and UI patterns.
- **Current price for unrealized PnL:** Use one of the user's **connected exchanges' public spot ticker endpoint** (no auth). Reuse pattern of `Positions::CurrentDataFetcher` + per-provider `TickerFetcher`; add spot symbol format (e.g. LDOUSDT) and spot API path. If user has no connected exchange, unrealized PnL can show as "—" or at breakeven until they connect one.
- **Fees (MVP):** Discard. Do not store or use fee/fee_currency in net USD or PnL; can add for display later.
- **Multiple spot balances:** One spot account per user for start; **schema supports multiple later** via `spot_accounts` (user_id, name, default). `spot_transactions` belongs to `spot_account_id`; MVP = one default spot_account per user.

---

## Summary

- **Spot portfolio tracker:** CSV-only input, content-based dedup, per-token balance, net USD, breakeven, epochs, realized/unrealized PnL (FIFO). **Current price** from a connected exchange's public spot ticker. **MVP: fees discarded.**
- **Schema:** `spot_accounts` (one per user for MVP; multiple later), `spot_transactions` (spot_account_id, row_signature for idempotency), optionally `spot_position_epochs`; no change to futures tables.
- **Idempotency:** Unique `(spot_account_id, row_signature)` on normalized row fields.
- **Separation + DRY:** Futures and spot in different tables; shared User, auth, UI, and price-fetcher pattern (extend with spot ticker endpoints).

Next: Run `/plan` to define implementation steps (spot_accounts + spot_transactions migration, CSV import, spot price fetcher, services, UI).
