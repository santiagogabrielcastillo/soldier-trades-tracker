---
date: 2026-04-08
topic: institute-multi-user
---

# Institute Multi-User Platform

## What We're Building

A multi-user educational layer on top of the existing personal investment tracker. Students register with a rotating invite code and get the full existing experience — isolated, tracking their own crypto futures, spot, stocks, and allocations. A new **admin role** gets a dedicated `/admin` namespace with a class-wide dashboard, aggregated statistics, and read-only drill-down into any individual student's portfolio.

Single institute scope (no multi-tenancy between organizations). All existing single-user behavior is unchanged.

## Why This Approach

**Approach B chosen: Dedicated `/admin` namespace** with shared View Components.

Approach A (context-switching "view as student" in the same controllers) was considered but rejected in favor of cleaner separation. Duplication is minimized by extracting shared UI into molecule-level View Components that both student views and admin views consume. Existing student views are refactored to use these components first, before admin views are built.

## Key Decisions

- **Admin namespace**: `/admin/` with its own controllers, views, and routes — clean boundary, no risk of bleedover
- **View Components — refactor first**: Extract molecule-level components from existing views before building admin. This gives a clean, DRY foundation for admin views.
- **Invite code**: Rotating DB record (`InviteCode` model) with expiry date — rotatable from admin UI without redeployment
- **Admin visibility**: Full read-only access to any student's portfolio; admins cannot write as a student
- **Aggregation**: On-the-fly SQL queries, no background caching — realized P&L only means no live price API calls; class size (tens of students) keeps query time well under 100ms
- **P&L metric**: Realized only — avoids live price fetching complexity for aggregates

## View Component Extraction Plan

The app already has atomic components (StatCardComponent, CardComponent, BadgeComponent, etc.). These molecule-level components need extracting first:

### `SummaryStatRowComponent` ← your "labeled rows" example
- Wraps the `flex flex-wrap items-baseline gap-6` container
- Slots: `with_stat(label:, value:, signed:, color_value:)`
- Used in: dashboard (10+ instances), stocks, spot, allocations, and future admin class overview
- Priority: **HIGH** — most instances

### `CardSectionComponent`
- Wraps `<section class="card-accent rounded-lg border border-slate-200 bg-white p-6 shadow-sm">` + `<h2>`
- Accepts: `title:`, optional `mb:`, optional `data:` for Stimulus controller binding
- Used in: dashboard (6 sections), allocations (4 sections), and all future admin sections
- Priority: **HIGH** — structural foundation

### `PageHeaderComponent`
- Wraps `<h1 class="text-2xl font-semibold text-slate-900">` + optional subtitle + optional right-side actions slot
- Used in: all 5 main views, all future admin views
- Priority: **MEDIUM**

### `DateRangeFilterComponent`
- Wraps the `auto-submit-form` Stimulus pattern + from/to date fields + "Clear filters" link
- Accepts: `url:`, `clear_url:`, `from:`, `to:`, optional extra field slots
- Used in: trades (×2), spot, future admin drill-down filters
- Priority: **MEDIUM**

## User Stories

### Student
- As a student, I can register with an institute invite code so access is restricted to institute members
- As a student, my data and experience is unchanged — I only ever see my own portfolio

### Admin — Class Performance Overview
- As an admin, I can see how many students are registered and active
- As an admin, I can see what % of students are net profitable across all asset types (realized P&L)
- As an admin, I can see average ROI across the class (futures, spot, stocks combined)
- As an admin, I can see a student leaderboard ranked by ROI or absolute P&L
- As an admin, I can see total capital deployed across the class

### Admin — Per-Student Drill-Down
- As an admin, I can browse a list of all students with summary metrics
- As an admin, I can view any student's full dashboard, trades, spot holdings, and stocks (read-only)
- As an admin, I can see a student's trade history and open positions

### Admin — Asset & Strategy Insights
- As an admin, I can see which symbols/assets are most traded across the class
- As an admin, I can see the distribution of long vs short positions class-wide
- As an admin, I can see average leverage used across students
- As an admin, I can see which asset type (futures/spot/stocks) is most active

### Admin — Invite Management
- As an admin, I can generate a new invite code with an expiry date
- As an admin, I can rotate (invalidate + regenerate) the current invite code
- As an admin, I can see when the current code expires

## Open Questions (resolved)
- Invite code expiry: yes, DB record with `expires_at`
- Aggregation caching: none, on-the-fly SQL
- P&L metric: realized only
- Refactor order: existing views first, then admin

## Open Questions (resolved)
- Leaderboard: admin-only, not visible to students
- "Active" student: manual boolean flag set by admin (`active` on User), no automated indicator for now

## Next Steps

→ `/ce:plan` for implementation details
