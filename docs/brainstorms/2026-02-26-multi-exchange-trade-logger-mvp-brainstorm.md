# Multi-Exchange Automated Trade Logger (MVP) — Brainstorm

**Date:** 2026-02-26  
**Source:** [docs/shaping.md](../shaping.md)

---

## What We're Building

A "set and forget" Rails 8 app that centralizes trade activity from multiple exchanges (Binance, BingX) without manual entry. Users link exchange accounts with read-only API keys; the system syncs trades on a **per-user** configurable schedule (e.g. Hourly, Daily, Twice daily), respects a per-account rate limit (e.g. max 2 runs/day per linked account), and stores a unified trade log. No Redis—Solid Queue only. Day 0 scope: only trades after account link; stablecoin pairs (USDT/USDC) only; API keys with Trade/Withdraw permissions rejected. Deployed with Kamal; code follows Rails conventions.

---

## Why This Approach

- **Provider pattern (A1):** Exchange-agnostic core so adding an exchange is a new strategy class, not schema changes. Keeps Trade model and sync loop unified.
- **Solid Queue (A2):** Aligns with appetite for a "Solid" stack and 2–3 week batch; no Redis dependency.
- **Config-driven intervals (A3):** Per-user configuration with a fixed set of options (Hourly, Daily, Twice daily) that drive Solid Queue scheduling directly—one interval for all of a user's linked accounts.
- **Rate limit (A8):** Cap sync runs per ExchangeAccount (e.g. max 2/day) so we stay within exchange API limits and avoid IP bans.
- **Encryption + read-only keys (A5, A6):** Security baseline; no write access to user funds.

---

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Job backend | Solid Queue only | No Redis; DB-backed, fits appetite. |
| Sync scope | Day 0 only | No historical backfill; keeps MVP bounded. |
| Pairs | USDT/USDC only | Avoid cross-rates and multi-leg logic for MVP. |
| Key permissions | Reject Trade/Withdraw | Read-only keys only before storing. |
| Sync interval scope | Per User | One interval for all of a user's linked accounts. |
| Interval options | Fixed set (Hourly, Daily, Twice daily) in config | Config drives Solid Queue directly; no static recurring.yml. |
| "Twice daily" semantics | Fixed times (e.g. 08:00 and 20:00 UTC) | Predictable; easy to schedule and enforce 2/day cap; avoids drift. |
| Rate limit | Per ExchangeAccount, e.g. max 2/day | Protects against exchange API limits per linked account. |
| Deployment | Kamal | Standard Rails deployment path; no Redis to orchestrate. |
| Code quality | Follow Rails conventions | Maintainability, consistency, and smooth upgrades; plan and reviews should enforce. |

---

## Resolved Questions

1. **Config scope:** Sync interval is **per User**—one setting for all of a user's linked accounts.
2. **"Twice daily" semantics:** **Fixed times** (e.g. 08:00 and 20:00 UTC). Recommendation: predictable scheduling, trivial 2/day enforcement, no drift; "every 12h from first sync" would spread load but complicates scheduling and cap logic.

---

## Deployment & Conventions

- **Kamal:** Use Kamal for deployment. Fits the Solid stack (no Redis); single- or multi-server rollout; secrets and env handled via Kamal config. Plan should include Kamal setup early so dev/prod parity is clear.
- **Rails conventions:** Apply standard Rails conventions (RESTful resources, fat models / thin controllers where it helps, service objects for exchange sync, Active Record encryption and Solid Queue as intended). This keeps the codebase maintainable, consistent, and upgrade-friendly; implementation plans and code reviews should explicitly check for convention adherence.

---

## Open Questions

None. Ready for planning.

---

## Repository Context

Greenfield project. No existing Rails app or conventions yet. Architecture and patterns are defined by the shaping doc and this brainstorm.
