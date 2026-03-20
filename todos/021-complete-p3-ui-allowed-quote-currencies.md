---
status: pending
priority: p3
issue_id: "021"
tags: [code-review, agent-native, ui, exchange-accounts]
dependencies: []
---

# No UI or controller action to view/update allowed_quote_currencies

## Problem Statement

PR #25 deliberately scoped out UI for `allowed_quote_currencies` ("configurable via Rails console only"). As a result, users and agents have no way to view or change the whitelist through the application. This creates a silent misconfiguration risk: a user could be missing USDC trades with no visible indicator.

Concretely:
- `ExchangeAccountsController` permits only `[:provider_type, :api_key, :api_secret]`
- No `update` route exists (`resources :exchange_accounts, only: %i[index new create destroy]`)
- The index view does not display the current whitelist
- A user linking a new account cannot specify their whitelist at creation time

## Proposed Solutions

### Option A: Minimal — show whitelist on index + add update action

1. Add `PATCH /exchange_accounts/:id` with:
   ```ruby
   def update
     if @exchange_account.update(update_params)
       redirect_to exchange_accounts_path, notice: "Settings updated"
     else
       render :edit, status: :unprocessable_entity
     end
   end

   def update_params
     params.require(:exchange_account).permit(allowed_quote_currencies: [])
   end
   ```
2. Add a simple edit form (checkboxes for each `SUPPORTED_QUOTE_CURRENCIES`)
3. Show active whitelist as a badge on the index view

**Effort:** Medium

### Option B: Defer to a follow-up PR (current state)

Track it here, implement when time permits.

**Effort:** None now

## Recommended Action

Option B for now (per PR scope). This todo tracks the follow-up work.

## Technical Details

**Files to change when implemented:**
- `config/routes.rb` — add `:edit, :update` to exchange_accounts resources
- `app/controllers/exchange_accounts_controller.rb` — add `edit`, `update`, `update_params`
- `app/views/exchange_accounts/edit.html.erb` — new view
- `app/views/exchange_accounts/index.html.erb` — show whitelist per account

## Acceptance Criteria

- [ ] Users can see their active whitelist on the exchange accounts index page
- [ ] Users can update `allowed_quote_currencies` via a form without console access
- [ ] `allowed_quote_currencies: []` is permitted in strong params
- [ ] Invalid values show validation errors
- [ ] New account creation (`new` form) also supports setting the whitelist

## Work Log

- 2026-03-19: Flagged as P1 by agent-native-reviewer during /ce:review of PR #25 (downgraded to P3 because PR explicitly defers UI)
