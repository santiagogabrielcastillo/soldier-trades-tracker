---
status: pending
priority: p1
issue_id: "015"
tags: [code-review, database, schema, migrations]
dependencies: []
---

# Schema drift: unrelated CEDEAR changes in db/schema.rb and db/queue_schema.rb

## Problem Statement

PR #25 (`feat/usdc-quote-currency-whitelist`) includes schema.rb and queue_schema.rb changes that belong to a different branch (`feat/cedear-argentina-stock-market`). These leaked in because the author ran `bin/rails db:migrate` locally with both sets of migrations applied. The committed schema does not match the PR's migration.

This blocks merge: if merged as-is, the CI/staging environment (which only has this PR's migration) will have a different schema than what's committed, causing schema version mismatches and potentially confusing future migrations.

## Findings

**From schema-drift-detector agent:**

Five unrelated changes in `db/schema.rb`:

1. **Entire `cedear_instruments` table** — two indexes, belongs to CEDEAR feature
2. **`add_foreign_key "cedear_instruments", "users"`** — no corresponding migration in this PR
3. **`t.string "market", default: "us", null: false`** on `stock_portfolios` — no migration
4. **`t.decimal "cedear_ratio", precision: 10, scale: 4`** on `stock_trades` — no migration
5. **Schema version `2026_03_19_185958`** instead of `2026_03_19_120000` (this PR's migration timestamp)

`db/queue_schema.rb` has the same spurious changes (16 lines added, not related to Solid Queue jobs).

The only legitimate schema.rb change for this PR is:
```ruby
t.jsonb "settings", default: {}, null: false  # on exchange_accounts
```

## Proposed Solutions

### Option A: Reset and re-migrate (Recommended)

```bash
git checkout master -- db/schema.rb
git checkout master -- db/queue_schema.rb
bin/rails db:migrate
git add db/schema.rb db/queue_schema.rb
git commit -m "fix: reset schema drift from local CEDEAR migrations"
```

**Pros:** Clean, simple, authoritative.
**Cons:** Requires checking that `bin/rails db:migrate` succeeds cleanly (it should).
**Effort:** Small
**Risk:** Low — master schema + one migration = deterministic output

### Option B: Manually edit schema.rb to remove drifted changes

Remove the four blocks manually and fix the version number.

**Pros:** No need to run migrations.
**Cons:** Error-prone, easy to miss a line or break formatting.
**Effort:** Medium
**Risk:** Medium — human editing of schema.rb is fragile

## Recommended Action

Option A.

## Technical Details

**Affected files:**
- `db/schema.rb`
- `db/queue_schema.rb`

**Verification after fix:**
```bash
git diff master -- db/schema.rb | grep "^+" | grep -v "settings"
# Expected: only schema version line and the settings column
```

## Acceptance Criteria

- [ ] `db/schema.rb` version is `2026_03_19_120000`
- [ ] No `cedear_instruments` table in schema.rb
- [ ] No `market` column on `stock_portfolios` in schema.rb
- [ ] No `cedear_ratio` column on `stock_trades` in schema.rb
- [ ] No `add_foreign_key "cedear_instruments"` in schema.rb
- [ ] `db/queue_schema.rb` contains no application table changes from this PR
- [ ] `bin/rails db:migrate` runs cleanly from a clean master checkout + this migration

## Work Log

- 2026-03-19: Detected by schema-drift-detector agent during /ce:review of PR #25

## Resources

- PR #25: feat(exchange-accounts): per-account quote currency whitelist with USDC support
- Migration: `db/migrate/20260319120000_add_settings_to_exchange_accounts.rb`
- Other branch: `feat/cedear-argentina-stock-market` (commit `038db3e`)
