# Spot Portfolio: In-App Add Transaction UI — Brainstorm

**Date:** 2026-03-10  
**Scope:** Add an in-app "New transaction" flow (modal, searchable token, buy/sell, amount, price, date) so users can add spot transactions without exporting CSV elsewhere and re-uploading. CSV upload stays for bulk/historical flexibility.

---

## What We're Building

1. **New transaction entry point** — A clear affordance on the spot portfolio page (e.g. "New transaction" button) that opens a modal.
2. **Modal form** — Fields: **token** (searchable select with type-to-search), **buy/sell**, **amount**, **price**, **date**. No fees in the form (user requested).
3. **Same data model** — Each submission creates a `SpotTransaction` (token, side, price_usd, amount, total_value_usd, executed_at, row_signature). `total_value_usd` = amount × price; `row_signature` derived from (executed_at, token, side, price_usd, amount) so duplicates are rejected.
4. **CSV stays** — CSV upload remains available for bulk imports and historical data; users get flexibility to add one-by-one in-app or upload a file.

---

## Why This Approach

- **Reduces friction** — No need to open another platform, export CSV, then upload here when adding a single trade.
- **Keeps flexibility** — CSV remains for power users and bulk/historical imports.
- **Reuses patterns** — App already has `<dialog>` + Stimulus for modals (e.g. trades index column picker); same pattern fits "New transaction."
- **No fee field** — Aligns with user preference; current model and CSV parser already treat fee as optional.

---

## Token List: Approaches

| Approach | Description | Pros | Cons |
|----------|-------------|------|------|
| **A: Static list** | Curated list of tokens (e.g. from app config or a JSON file). Filter in frontend as user types. | Simple; no external API; fast; works offline. | List can become stale; must maintain. |
| **B: API-backed (e.g. Binance)** | Endpoint that fetches tradeable symbols from Binance (or similar) and optionally caches. Frontend requests filtered list or full list and filters. | Always up to date; covers any symbol the exchange lists. | Depends on external service; rate limits; slightly more code. |
| **C: Hybrid** | Start with static list (e.g. top N + tokens already used in this account from DB). Option to add "fetch from exchange" later. | Ships fast; good UX for common tokens; can evolve. | Two code paths if we add API later. |

**Recommendation:** **C (Hybrid)** — tokens already in user's spot account + static list; good UX for returning users and new users.

---

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| CSV upload | Stays alongside new flow | User confirmed: more flexibility for bulk/historical; modal for one-by-one. |
| Form fields | Token, buy/sell, amount, price, date; no fees | Matches user description and existing model; total_value_usd computed. |
| Modal pattern | Native `<dialog>` + Stimulus (same as trades columns) | Already in codebase; consistent UX. |
| Token source (first version) | Hybrid: tokens in account + static list | User's tokens first; static list for discovery; no API dependency for v1. |

---

## Resolved Questions

- **CSV stays?** → Yes; keep CSV for flexibility (bulk/historical).
- **Fees in form?** → No; user doesn't want them.
- **Difficulty?** → Moderate: modal + form is straightforward; token search is the only new piece (static or API).

---

## Resolved (token list)

- **Token list for v1** → Hybrid: tokens already in user's spot account + static list. Endpoint or inline data returns "tokens in account"; frontend merges with static list and filters as user types.

---

## Summary

- Add **"New transaction"** on spot portfolio page opening a **modal** with token (searchable), buy/sell, amount, price, date.
- **CSV upload stays** for bulk/historical.
- Use existing **dialog + Stimulus** pattern; new transaction creates `SpotTransaction` with computed `total_value_usd` and `row_signature`.
- Token list: **hybrid** — tokens in account + static list; API-backed search can be a follow-up.

Next: run `/plan` when ready to implement, or clarify the token-list open question first.
