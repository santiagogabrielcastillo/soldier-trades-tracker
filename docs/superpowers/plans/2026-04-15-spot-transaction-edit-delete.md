# Spot Transaction Edit & Delete — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add inline edit and delete to the Spot Transactions view using shared Turbo Frame modals, with automatic recalculation of all position metrics on save.

**Architecture:** Two shared `<dialog>` modals live once on the page; clicking Edit/Delete on a row loads content into the modal's `<turbo-frame>` via a GET request, which fires `turbo:frame-load` and opens the dialog via a new `turbo-modal` Stimulus controller. Edit submits PATCH, delete confirm submits DELETE. `PositionStateService` recomputes everything from scratch on each page load — no explicit recalculation needed.

**Tech Stack:** Rails 7, Turbo Frames, Hotwire Stimulus, Tailwind CSS, Minitest

---

## File Map

| Action | File |
|---|---|
| Create | `app/views/spot/_edit_form.html.erb` |
| Create | `app/views/spot/_delete_confirm.html.erb` |
| Create | `app/javascript/controllers/turbo_modal_controller.js` |
| Modify | `config/routes.rb` |
| Modify | `app/controllers/spot_controller.rb` |
| Modify | `app/views/spot/index.html.erb` |
| Modify | `test/controllers/spot_controller_test.rb` |

---

## Task 1: Add Routes

**Files:**
- Modify: `config/routes.rb:36-39`

- [ ] **Step 1: Add 4 new routes after the existing spot routes**

Open `config/routes.rb`. After line 39 (`post "spot/sync_prices"...`), add:

```ruby
  get    "spot/transactions/:id/edit",    to: "spot#edit",            as: :edit_spot_transaction
  get    "spot/transactions/:id/confirm", to: "spot#confirm_destroy", as: :confirm_destroy_spot_transaction
  patch  "spot/transactions/:id",         to: "spot#update",          as: :spot_transaction
  delete "spot/transactions/:id",         to: "spot#destroy",         as: :destroy_spot_transaction
```

The existing `post "spot/transactions"` route uses no `:id` segment, so these new routes won't conflict.

- [ ] **Step 2: Verify routes exist**

```bash
bin/rails routes | grep spot_transaction
```

Expected output includes these 5 lines:
```
spot_transactions  POST  /spot/transactions           spot#create
edit_spot_transaction  GET   /spot/transactions/:id/edit    spot#edit
confirm_destroy_spot_transaction GET /spot/transactions/:id/confirm spot#confirm_destroy
spot_transaction  PATCH  /spot/transactions/:id       spot#update
                  DELETE /spot/transactions/:id       spot#destroy
```

- [ ] **Step 3: Commit**

```bash
git add config/routes.rb
git commit -m "feat(routes): add edit, update, confirm_destroy, destroy for spot transactions"
```

---

## Task 2: destroy Action

**Files:**
- Modify: `app/controllers/spot_controller.rb`
- Modify: `test/controllers/spot_controller_test.rb`

- [ ] **Step 1: Write the failing tests**

Add to `test/controllers/spot_controller_test.rb` before the `sign_in_as` helper method:

```ruby
test "destroy deletes own transaction and redirects with notice" do
  sign_in_as(@user)
  account = SpotAccount.find_or_create_default_for(@user)
  tx = account.spot_transactions.create!(
    token: "BTC", side: "buy", amount: 1, price_usd: 50_000, total_value_usd: 50_000,
    executed_at: 1.day.ago, row_signature: SecureRandom.hex(32)
  )
  assert_difference("account.spot_transactions.count", -1) do
    delete destroy_spot_transaction_path(tx)
  end
  assert_redirected_to spot_path(view: "transactions")
  assert_equal "Transaction deleted.", flash[:notice]
end

test "destroy returns 404 for another user's transaction" do
  sign_in_as(@user)
  other_user = users(:two)
  other_user.update!(password: "password", password_confirmation: "password")
  other_account = SpotAccount.find_or_create_default_for(other_user)
  tx = other_account.spot_transactions.create!(
    token: "ETH", side: "buy", amount: 1, price_usd: 3_000, total_value_usd: 3_000,
    executed_at: 1.day.ago, row_signature: SecureRandom.hex(32)
  )
  assert_no_difference("SpotTransaction.count") do
    delete destroy_spot_transaction_path(tx)
  end
  assert_response :not_found
end
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
bin/rails test test/controllers/spot_controller_test.rb -n "/destroy/"
```

Expected: 2 failures — `AbstractController::ActionNotFound: The action 'destroy' could not be found`

- [ ] **Step 3: Implement the destroy action**

In `app/controllers/spot_controller.rb`, add the `destroy` action inside the `private`-section boundary (before `private`):

```ruby
def destroy
  @spot_account = SpotAccount.find_or_create_default_for(current_user)
  @transaction = @spot_account.spot_transactions.find(params[:id])
  @transaction.destroy!
  redirect_to spot_path(view: "transactions"), notice: "Transaction deleted."
end
```

- [ ] **Step 4: Run tests to confirm they pass**

```bash
bin/rails test test/controllers/spot_controller_test.rb -n "/destroy/"
```

Expected: 2 runs, 0 failures, 0 errors

- [ ] **Step 5: Commit**

```bash
git add app/controllers/spot_controller.rb test/controllers/spot_controller_test.rb
git commit -m "feat(spot): add destroy action for spot transactions"
```

---

## Task 3: edit Action and _edit_form Partial

**Files:**
- Modify: `app/controllers/spot_controller.rb`
- Create: `app/views/spot/_edit_form.html.erb`
- Modify: `test/controllers/spot_controller_test.rb`

- [ ] **Step 1: Write the failing tests**

Add to `test/controllers/spot_controller_test.rb`:

```ruby
test "edit returns the edit form partial for own transaction" do
  sign_in_as(@user)
  account = SpotAccount.find_or_create_default_for(@user)
  tx = account.spot_transactions.create!(
    token: "BTC", side: "buy", amount: 1, price_usd: 50_000, total_value_usd: 50_000,
    executed_at: 1.day.ago, row_signature: SecureRandom.hex(32)
  )
  get edit_spot_transaction_path(tx)
  assert_response :success
  assert_match(/BTC/, response.body)
  assert_match(/50000/, response.body)
  assert_match(/spot-transaction-edit-frame/, response.body)
end

test "edit returns 404 for another user's transaction" do
  sign_in_as(@user)
  other_user = users(:two)
  other_user.update!(password: "password", password_confirmation: "password")
  other_account = SpotAccount.find_or_create_default_for(other_user)
  tx = other_account.spot_transactions.create!(
    token: "ETH", side: "buy", amount: 1, price_usd: 3_000, total_value_usd: 3_000,
    executed_at: 1.day.ago, row_signature: SecureRandom.hex(32)
  )
  get edit_spot_transaction_path(tx)
  assert_response :not_found
end
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
bin/rails test test/controllers/spot_controller_test.rb -n "/edit/"
```

Expected: 2 failures — action not found

- [ ] **Step 3: Add the edit action**

In `app/controllers/spot_controller.rb`, add before `private`:

```ruby
def edit
  @spot_account = SpotAccount.find_or_create_default_for(current_user)
  @transaction = @spot_account.spot_transactions.find(params[:id])
  render partial: "edit_form", locals: { transaction: @transaction }
end
```

- [ ] **Step 4: Create the edit form partial**

Create `app/views/spot/_edit_form.html.erb`:

```erb
<%= turbo_frame_tag "spot-transaction-edit-frame" do %>
  <h2 class="mb-4 text-lg font-semibold text-slate-900">Edit transaction</h2>

  <%= form_with url: spot_transaction_path(transaction), method: :patch do |f| %>
    <div class="space-y-4">
      <div>
        <span class="block text-sm font-medium text-slate-700">Side</span>
        <p class="mt-1 text-sm capitalize text-slate-900"><%= transaction.side %></p>
      </div>

      <% if transaction.side.in?(%w[buy sell]) %>
        <div>
          <%= f.label :token, "Token", class: "block text-sm font-medium text-slate-700" %>
          <%= f.text_field :token, value: transaction.token, class: "w-full rounded-md border border-slate-300 px-3 py-2 text-sm focus:border-slate-500 focus:outline-none focus:ring-1 focus:ring-slate-500" %>
          <% if transaction.errors[:token].any? %>
            <p class="mt-1 text-sm text-red-600"><%= transaction.errors[:token].first %></p>
          <% end %>
        </div>
      <% end %>

      <div>
        <%= f.label :amount, "Amount", class: "block text-sm font-medium text-slate-700" %>
        <%= f.number_field :amount, value: transaction.amount, step: :any, min: 0, placeholder: "0", class: "w-full rounded-md border border-slate-300 px-3 py-2 text-sm focus:border-slate-500 focus:outline-none focus:ring-1 focus:ring-slate-500" %>
        <% if transaction.errors[:amount].any? %>
          <p class="mt-1 text-sm text-red-600"><%= transaction.errors[:amount].first %></p>
        <% end %>
      </div>

      <% if transaction.side.in?(%w[buy sell]) %>
        <div>
          <%= f.label :price_usd, "Price (USD)", class: "block text-sm font-medium text-slate-700" %>
          <%= f.number_field :price_usd, value: transaction.price_usd, step: :any, min: 0, placeholder: "0", class: "w-full rounded-md border border-slate-300 px-3 py-2 text-sm focus:border-slate-500 focus:outline-none focus:ring-1 focus:ring-slate-500" %>
          <% if transaction.errors[:price_usd].any? %>
            <p class="mt-1 text-sm text-red-600"><%= transaction.errors[:price_usd].first %></p>
          <% end %>
        </div>
      <% end %>

      <div>
        <%= f.label :executed_at, "Date & time", class: "block text-sm font-medium text-slate-700" %>
        <%= f.datetime_local_field :executed_at, value: transaction.executed_at.strftime("%Y-%m-%dT%H:%M"), class: "w-full rounded-md border border-slate-300 px-3 py-2 text-sm focus:border-slate-500 focus:outline-none focus:ring-1 focus:ring-slate-500" %>
        <p class="mt-1 text-xs text-slate-500">Interpreted in <%= Time.zone.name %> and stored in UTC.</p>
        <% if transaction.errors[:executed_at].any? %>
          <p class="mt-1 text-sm text-red-600"><%= transaction.errors[:executed_at].first %></p>
        <% end %>
      </div>

      <% if transaction.errors[:base].any? %>
        <p class="text-sm text-red-600"><%= transaction.errors[:base].first %></p>
      <% end %>
    </div>

    <div class="mt-6 flex gap-2">
      <%= f.submit "Save changes", class: "rounded-md bg-slate-800 px-4 py-2 text-sm font-medium text-white hover:bg-slate-700 focus:outline-none focus:ring-2 focus:ring-slate-500" %>
      <button type="button" data-action="click->turbo-modal#close" class="rounded-md border border-slate-300 bg-white px-4 py-2 text-sm text-slate-700 hover:bg-slate-50">Cancel</button>
    </div>
  <% end %>
<% end %>
```

- [ ] **Step 5: Run tests to confirm they pass**

```bash
bin/rails test test/controllers/spot_controller_test.rb -n "/edit/"
```

Expected: 2 runs, 0 failures, 0 errors

- [ ] **Step 6: Commit**

```bash
git add app/controllers/spot_controller.rb app/views/spot/_edit_form.html.erb test/controllers/spot_controller_test.rb
git commit -m "feat(spot): add edit action and edit form partial"
```

---

## Task 4: confirm_destroy Action and _delete_confirm Partial

**Files:**
- Modify: `app/controllers/spot_controller.rb`
- Create: `app/views/spot/_delete_confirm.html.erb`
- Modify: `test/controllers/spot_controller_test.rb`

- [ ] **Step 1: Write the failing tests**

Add to `test/controllers/spot_controller_test.rb`:

```ruby
test "confirm_destroy returns delete confirm partial for own transaction" do
  sign_in_as(@user)
  account = SpotAccount.find_or_create_default_for(@user)
  tx = account.spot_transactions.create!(
    token: "BTC", side: "buy", amount: 1, price_usd: 50_000, total_value_usd: 50_000,
    executed_at: 1.day.ago, row_signature: SecureRandom.hex(32)
  )
  get confirm_destroy_spot_transaction_path(tx)
  assert_response :success
  assert_match(/BTC/, response.body)
  assert_match(/spot-transaction-delete-frame/, response.body)
  assert_match(/Confirm delete/, response.body)
end

test "confirm_destroy returns 404 for another user's transaction" do
  sign_in_as(@user)
  other_user = users(:two)
  other_user.update!(password: "password", password_confirmation: "password")
  other_account = SpotAccount.find_or_create_default_for(other_user)
  tx = other_account.spot_transactions.create!(
    token: "ETH", side: "buy", amount: 1, price_usd: 3_000, total_value_usd: 3_000,
    executed_at: 1.day.ago, row_signature: SecureRandom.hex(32)
  )
  get confirm_destroy_spot_transaction_path(tx)
  assert_response :not_found
end
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
bin/rails test test/controllers/spot_controller_test.rb -n "/confirm_destroy/"
```

Expected: 2 failures — action not found

- [ ] **Step 3: Add the confirm_destroy action**

In `app/controllers/spot_controller.rb`, add before `private`:

```ruby
def confirm_destroy
  @spot_account = SpotAccount.find_or_create_default_for(current_user)
  @transaction = @spot_account.spot_transactions.find(params[:id])
  render partial: "delete_confirm", locals: { transaction: @transaction }
end
```

- [ ] **Step 4: Create the delete confirm partial**

Create `app/views/spot/_delete_confirm.html.erb`:

```erb
<%= turbo_frame_tag "spot-transaction-delete-frame" do %>
  <h2 class="mb-4 text-lg font-semibold text-slate-900">Delete transaction</h2>

  <p class="mb-6 text-sm text-slate-600">
    Are you sure you want to delete this
    <span class="font-medium capitalize"><%= transaction.token %> <%= transaction.side %></span>
    of <span class="font-medium"><%= number_with_delimiter(transaction.amount.to_f, delimiter: ",") %></span>
    on <span class="font-medium"><%= transaction.executed_at.strftime("%b %d, %Y") %></span><% unless transaction.side.in?(%w[deposit withdraw]) %> at <span class="font-medium"><%= format_money(transaction.price_usd) %></span><% end %>?
    <br><span class="font-medium text-red-600">This cannot be undone.</span>
  </p>

  <div class="flex gap-2">
    <%= button_to "Confirm delete", destroy_spot_transaction_path(transaction), method: :delete,
        class: "rounded-md bg-red-600 px-4 py-2 text-sm font-medium text-white hover:bg-red-700 focus:outline-none focus:ring-2 focus:ring-red-500" %>
    <button type="button" data-action="click->turbo-modal#close"
        class="rounded-md border border-slate-300 bg-white px-4 py-2 text-sm text-slate-700 hover:bg-slate-50">
      Cancel
    </button>
  </div>
<% end %>
```

- [ ] **Step 5: Run tests to confirm they pass**

```bash
bin/rails test test/controllers/spot_controller_test.rb -n "/confirm_destroy/"
```

Expected: 2 runs, 0 failures, 0 errors

- [ ] **Step 6: Commit**

```bash
git add app/controllers/spot_controller.rb app/views/spot/_delete_confirm.html.erb test/controllers/spot_controller_test.rb
git commit -m "feat(spot): add confirm_destroy action and delete confirm partial"
```

---

## Task 5: update Action

**Files:**
- Modify: `app/controllers/spot_controller.rb`
- Modify: `test/controllers/spot_controller_test.rb`

- [ ] **Step 1: Write the failing tests**

Add to `test/controllers/spot_controller_test.rb`:

```ruby
test "update with valid params corrects price and recalculates total_value_usd and row_signature" do
  sign_in_as(@user)
  account = SpotAccount.find_or_create_default_for(@user)
  tx = account.spot_transactions.create!(
    token: "BTC", side: "buy", amount: BigDecimal("2"), price_usd: BigDecimal("50000"),
    total_value_usd: BigDecimal("100000"), executed_at: Time.zone.parse("2026-01-10 12:00"),
    row_signature: SecureRandom.hex(32)
  )
  old_sig = tx.row_signature

  patch spot_transaction_path(tx), params: {
    token: "BTC", price_usd: "55000", amount: "2", executed_at: "2026-01-10T12:00"
  }

  assert_redirected_to spot_path(view: "transactions")
  assert_equal "Transaction updated.", flash[:notice]
  tx.reload
  assert_equal BigDecimal("55000"), tx.price_usd
  assert_equal BigDecimal("110000"), tx.total_value_usd
  assert_not_equal old_sig, tx.row_signature
end

test "update with duplicate values shows validation error and re-renders form" do
  sign_in_as(@user)
  account = SpotAccount.find_or_create_default_for(@user)
  existing = account.spot_transactions.create!(
    token: "BTC", side: "buy", amount: BigDecimal("1"), price_usd: BigDecimal("60000"),
    total_value_usd: BigDecimal("60000"), executed_at: Time.zone.parse("2026-01-10 12:00"),
    row_signature: Spot::CsvRowParser.row_signature(Time.zone.parse("2026-01-10 12:00"), "BTC", "buy", BigDecimal("60000"), BigDecimal("1"))
  )
  tx = account.spot_transactions.create!(
    token: "BTC", side: "buy", amount: BigDecimal("2"), price_usd: BigDecimal("50000"),
    total_value_usd: BigDecimal("100000"), executed_at: Time.zone.parse("2026-01-11 12:00"),
    row_signature: SecureRandom.hex(32)
  )

  # Attempt to update tx so its values collide with existing
  patch spot_transaction_path(tx), params: {
    token: "BTC", price_usd: "60000", amount: "1", executed_at: "2026-01-10T12:00"
  }

  assert_response :unprocessable_entity
  assert_match(/spot-transaction-edit-frame/, response.body)
end

test "update cannot update another user's transaction" do
  sign_in_as(@user)
  other_user = users(:two)
  other_user.update!(password: "password", password_confirmation: "password")
  other_account = SpotAccount.find_or_create_default_for(other_user)
  tx = other_account.spot_transactions.create!(
    token: "ETH", side: "buy", amount: 1, price_usd: 3_000, total_value_usd: 3_000,
    executed_at: 1.day.ago, row_signature: SecureRandom.hex(32)
  )
  patch spot_transaction_path(tx), params: {
    token: "ETH", price_usd: "4000", amount: "1", executed_at: 1.day.ago.strftime("%Y-%m-%dT%H:%M")
  }
  assert_response :not_found
  tx.reload
  assert_equal BigDecimal("3000"), tx.price_usd
end

test "update deposit transaction changes amount and recalculates total_value_usd" do
  sign_in_as(@user)
  account = SpotAccount.find_or_create_default_for(@user)
  tx = account.spot_transactions.create!(
    token: "USDT", side: "deposit", amount: BigDecimal("100"), price_usd: BigDecimal("1"),
    total_value_usd: BigDecimal("100"), executed_at: Time.zone.parse("2026-01-10 12:00"),
    row_signature: "cash|#{Time.zone.parse("2026-01-10 12:00").to_i}|abc123"
  )
  patch spot_transaction_path(tx), params: {
    amount: "250", executed_at: "2026-01-10T12:00"
  }
  assert_redirected_to spot_path(view: "transactions")
  tx.reload
  assert_equal BigDecimal("250"), tx.amount
  assert_equal BigDecimal("250"), tx.total_value_usd
end
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
bin/rails test test/controllers/spot_controller_test.rb -n "/update/"
```

Expected: 4 failures — action not found

- [ ] **Step 3: Implement the update action**

In `app/controllers/spot_controller.rb`, add before `private`:

```ruby
def update
  @spot_account = SpotAccount.find_or_create_default_for(current_user)
  @transaction = @spot_account.spot_transactions.find(params[:id])

  permitted = spot_transaction_params
  executed_at = parse_executed_at(permitted[:executed_at])
  amount = parse_decimal_param(permitted[:amount])

  attrs = build_update_attrs(@transaction, permitted, executed_at, amount)

  if attrs && @transaction.update(attrs)
    redirect_to spot_path(view: "transactions"), notice: "Transaction updated."
  else
    @transaction.errors.add(:base, "Invalid parameters.") if attrs.nil?
    render partial: "edit_form", locals: { transaction: @transaction }, status: :unprocessable_entity
  end
end
```

Then add the private helper at the bottom of the private section:

```ruby
def build_update_attrs(transaction, permitted, executed_at, amount)
  return nil unless executed_at && amount && amount.positive?

  if transaction.side.in?(%w[deposit withdraw])
    total_value_usd = amount
    row_signature = "cash|#{executed_at.to_i}|#{transaction.id}"
    { amount: amount, executed_at: executed_at, total_value_usd: total_value_usd, row_signature: row_signature }
  else
    token = permitted[:token].to_s.strip.upcase.presence
    price_usd = parse_decimal_param(permitted[:price_usd])
    return nil unless token && price_usd && price_usd >= 0

    total_value_usd = amount * price_usd
    row_signature = Spot::CsvRowParser.row_signature(executed_at, token, transaction.side, price_usd, amount)
    { token: token, price_usd: price_usd, amount: amount, executed_at: executed_at, total_value_usd: total_value_usd, row_signature: row_signature }
  end
end
```

- [ ] **Step 4: Run tests to confirm they pass**

```bash
bin/rails test test/controllers/spot_controller_test.rb -n "/update/"
```

Expected: 4 runs, 0 failures, 0 errors

- [ ] **Step 5: Run the full spot controller test suite**

```bash
bin/rails test test/controllers/spot_controller_test.rb
```

Expected: all pass

- [ ] **Step 6: Commit**

```bash
git add app/controllers/spot_controller.rb test/controllers/spot_controller_test.rb
git commit -m "feat(spot): add update action with recalculation of total_value_usd and row_signature"
```

---

## Task 6: turbo-modal Stimulus Controller

**Files:**
- Create: `app/javascript/controllers/turbo_modal_controller.js`

The existing `dialog_controller.js` handles `openOnConnect` but knows nothing about Turbo Frames. This new controller wraps a `<dialog>` + `<turbo-frame>` pair: when the frame loads content it opens the dialog; closing clears the frame so it's ready for the next row.

- [ ] **Step 1: Create the controller**

Create `app/javascript/controllers/turbo_modal_controller.js`:

```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dialog", "frame"]

  open() {
    if (this.hasDialogTarget) {
      this.dialogTarget.showModal()
    }
  }

  close() {
    if (this.hasDialogTarget) {
      this.dialogTarget.close()
    }
    if (this.hasFrameTarget) {
      this.frameTarget.innerHTML = ""
    }
  }
}
```

Stimulus auto-discovers controllers via `eagerLoadControllersFrom` in `controllers/index.js` — no registration step needed. The file name `turbo_modal_controller.js` maps to the identifier `turbo-modal`.

- [ ] **Step 2: Verify auto-discovery will pick it up**

```bash
grep -n "eagerLoadControllersFrom" app/javascript/controllers/index.js
```

Expected output: `eagerLoadControllersFrom("controllers", application)` — confirms auto-discovery is active.

- [ ] **Step 3: Commit**

```bash
git add app/javascript/controllers/turbo_modal_controller.js
git commit -m "feat(js): add turbo-modal Stimulus controller for Turbo Frame modals"
```

---

## Task 7: Wire Up the Index View

**Files:**
- Modify: `app/views/spot/index.html.erb`

This task has two parts: add an Actions column to the transactions table, and add the two shared modals at the bottom of the transactions view.

- [ ] **Step 1: Add the Actions column header to the DataTable**

In `app/views/spot/index.html.erb`, find the `DataTableComponent` for transactions (around line 150). Change the columns array to add an Actions column at the end:

```erb
<%= render DataTableComponent.new(columns: [
  { label: "Date", classes: "text-left" },
  { label: "Token", classes: "text-left" },
  { label: "Side", classes: "text-left" },
  { label: "Amount", classes: "text-right" },
  { label: "Price (USD)", classes: "text-right" },
  { label: "Total value (USD)", classes: "text-right" },
  { label: "", classes: "text-right" }
]) do |table| %>
```

- [ ] **Step 2: Add Edit and Delete buttons to each row**

Still in the `@transactions.each` block, after the last `<td>` (Total value USD), add a new cell:

```erb
<td class="whitespace-nowrap px-6 py-4 text-right text-sm">
  <%= link_to "Edit", edit_spot_transaction_path(tx),
      data: { turbo_frame: "spot-transaction-edit-frame" },
      class: "mr-3 text-slate-500 underline hover:text-slate-800" %>
  <%= link_to "Delete", confirm_destroy_spot_transaction_path(tx),
      data: { turbo_frame: "spot-transaction-delete-frame" },
      class: "text-red-500 underline hover:text-red-700" %>
</td>
```

- [ ] **Step 3: Add the two shared modals after the transactions table (but still inside the `@view == "transactions"` block)**

Add this block just before the closing `<% end %>` of the `if @view == "transactions"` block (after the pagination div and empty-state render):

```erb
<%# Shared edit modal — content loaded on demand via Turbo Frame %>
<div data-controller="turbo-modal">
  <dialog data-turbo-modal-target="dialog"
          class="w-full max-w-md rounded-lg border border-slate-200 bg-white p-6 shadow-xl backdrop:bg-slate-900/20">
    <turbo-frame id="spot-transaction-edit-frame"
                 data-turbo-modal-target="frame"
                 data-action="turbo:frame-load->turbo-modal#open">
    </turbo-frame>
  </dialog>
</div>

<%# Shared delete confirm modal — content loaded on demand via Turbo Frame %>
<div data-controller="turbo-modal">
  <dialog data-turbo-modal-target="dialog"
          class="w-full max-w-md rounded-lg border border-slate-200 bg-white p-6 shadow-xl backdrop:bg-slate-900/20">
    <turbo-frame id="spot-transaction-delete-frame"
                 data-turbo-modal-target="frame"
                 data-action="turbo:frame-load->turbo-modal#open">
    </turbo-frame>
  </dialog>
</div>
```

- [ ] **Step 4: Commit**

```bash
git add app/views/spot/index.html.erb
git commit -m "feat(spot): add Edit/Delete buttons and shared Turbo Frame modals to transactions view"
```

---

## Task 8: Smoke Test in Browser

- [ ] **Step 1: Start the dev server**

```bash
./bin/dev
```

- [ ] **Step 2: Test the edit flow**
1. Navigate to `http://localhost:5000/spot?view=transactions`
2. Click **Edit** on a buy transaction — the edit modal should open pre-filled with the transaction's values
3. Change the price to an incorrect value and click **Save changes** — verify validation error appears inline inside the modal
4. Change the price to a correct value, click **Save changes** — modal closes, you're redirected to transactions view, flash notice appears
5. Verify the updated price appears in the table

- [ ] **Step 3: Test the delete flow**
1. Click **Delete** on a transaction — the confirmation modal should open showing the transaction details
2. Click **Cancel** — modal closes, nothing deleted
3. Click **Delete** again, then **Confirm delete** — redirected to transactions view, transaction is gone, flash notice appears

- [ ] **Step 4: Test the portfolio view recalculates**
1. Navigate to `http://localhost:5000/spot` (portfolio tab)
2. Verify that breakeven (avg buy price) and unrealized ROI/PnL now reflect the corrected price

- [ ] **Step 5: Run the full test suite**

```bash
bin/rails test
```

Expected: all pass
