# Spot Transaction Edit & Delete — Design Spec

**Date:** 2026-04-15
**Branch:** deep-stock-analysis
**Status:** Approved

## Problem

Users can create spot transactions manually but have no way to correct mistakes. A wrong price on a buy transaction corrupts the breakeven, unrealized PnL, and ROI for that token. The only current workaround is deleting and re-importing via CSV, which is impractical for single corrections.

## Goal

Add inline edit and delete capabilities to the Transactions view, with recalculation of all position metrics happening automatically on save.

## Approach: Shared Turbo Frame Modals

One edit modal and one delete confirm modal live in the page (rendered once, outside the row loop). Clicking a row action loads content into the modal's Turbo Frame, then opens it via Stimulus. This avoids rendering N modals for N rows and fits the existing dialog Stimulus + Hotwire patterns.

## Routes

```
GET    /spot/transactions/:id/edit  → spot#edit
PATCH  /spot/transactions/:id       → spot#update
DELETE /spot/transactions/:id       → spot#destroy
```

## Controller

### `edit`
- Scopes lookup: `@spot_account.spot_transactions.find(params[:id])`
- Renders a partial (`_edit_form.html.erb`) inside a Turbo Frame
- No redirect

### `update`
1. Find transaction scoped to `current_user`'s spot account (404 if not found)
2. Permit: `token`, `price_usd`, `amount`, `executed_at` — **`side` is not editable**
3. Recalculate `total_value_usd = amount × price_usd`
4. Regenerate `row_signature` via `Spot::CsvRowParser.row_signature(executed_at, token, side, price_usd, amount)`
5. Save:
   - **Success:** redirect to `spot_path(view: "transactions")`, flash notice
   - **Validation error:** re-render partial inside Turbo Frame with inline errors (422)
   - **Duplicate signature:** surfaces as a validation error ("This transaction already exists.")

### `destroy`
1. Find transaction scoped to `current_user`'s spot account
2. Destroy
3. Redirect to `spot_path(view: "transactions")`, flash notice
4. On unexpected error: redirect with flash alert

## View Changes

### Transactions table
- Add a rightmost **"Actions"** column (no header label, or "Actions")
- Each row gets two buttons:
  - **Edit** — ghost/secondary style, pencil icon or "Edit" label
  - **Delete** — destructive-tinted style, trash icon or "Delete" label
- Edit button: `data-turbo-frame="spot-transaction-edit-frame"`, links to `edit_spot_transaction_path(tx)`
- Delete button: `data-turbo-frame="spot-transaction-delete-frame"`, links to `spot_transaction_path(tx)` with a confirm param or dedicated path

### Shared modals (rendered once, outside the loop)
Two modals at the bottom of the transactions view section:

**Edit modal**
```
<dialog> (opened by dialog Stimulus controller)
  <turbo-frame id="spot-transaction-edit-frame">
    <!-- form partial loads here on demand -->
  </turbo-frame>
</dialog>
```

**Delete confirm modal**
```
<dialog> (opened by dialog Stimulus controller)
  <turbo-frame id="spot-transaction-delete-frame">
    <!-- confirm fragment loads here on demand -->
  </turbo-frame>
</dialog>
```

A Stimulus controller (extend existing `dialog` controller or add a thin `turbo-modal` controller) listens for `turbo:frame-load` on each frame and calls `open` on the parent dialog.

### Partials
- `app/views/spot/_edit_form.html.erb` — pre-filled form, wrapped in `turbo_frame_tag "spot-transaction-edit-frame"`. Fields: token (read-only or editable), amount, price_usd, executed_at. Side is displayed as read-only text, not an input.
- `app/views/spot/_delete_confirm.html.erb` — wrapped in `turbo_frame_tag "spot-transaction-delete-frame"`. Shows a summary of the transaction ("Delete BTC buy of 0.5 on Apr 10, 2026 at $82,000?") and a styled "Confirm delete" `button_to` that sends `DELETE`.

## Security

All lookups are scoped through `current_user`'s spot account:
```ruby
@spot_account = SpotAccount.find_or_create_default_for(current_user)
@transaction = @spot_account.spot_transactions.find(params[:id])
```
Returns 404 (via `ActiveRecord::RecordNotFound`) if the transaction doesn't belong to the user.

## What Is Not Editable

`side` (buy/sell/deposit/withdraw) is intentionally not editable. Changing side would alter position history in ways that are hard to reason about. If the side is wrong, the user should delete the transaction and create a new one.

## Recalculation

No explicit recalculation step is needed. `Spot::PositionStateService` reads all transactions fresh on every page load and recomputes breakeven, balance, realized PnL, and unrealized metrics from scratch. Saving or deleting a transaction is sufficient.

## Error States

| Scenario | Behavior |
|---|---|
| Duplicate `row_signature` after edit | Validation error inline: "This transaction already exists." |
| Blank/invalid price or amount | Inline field errors in edit modal |
| Transaction not found (wrong user) | 404 |
| Delete fails unexpectedly | Redirect with flash alert |
