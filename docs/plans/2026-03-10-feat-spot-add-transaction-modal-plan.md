# feat: Spot portfolio — in-app Add transaction modal

---
title: Spot portfolio in-app Add transaction modal
type: feat
status: completed
date: 2026-03-10
source_brainstorm: docs/brainstorms/2026-03-10-spot-add-transaction-ui-brainstorm.md
---

## Enhancement Summary (Deepen pass)

**Deepened on:** 2026-03-10  
**Sections added:** Research (UI & Accessibility, Datetime & Timezone, Modal + Validation Errors).  
**Research sources:** Adrian Roselli (datalist a11y), Pope Tech (ARIA combobox), Rails datetime/timezone (SO), modal validation pattern (render vs redirect).

### Key improvements from research

1. **Token UI:** Use an **ARIA combobox** instead of `<datalist>` for accessible, cross-browser token search (datalist has issues on Firefox Android, iOS 26, voice control, zoom).
2. **Validation errors:** On create failure, **render :index** with `@open_new_transaction_modal = true` and `@spot_transaction` (with errors) so the modal reopens with field errors; avoid redirect which loses errors.
3. **Datetime:** Document that submitted datetime is interpreted in the app default time zone and stored in UTC; optional later: user timezone preference.

---

## Overview

Add an in-app "New transaction" flow on the spot portfolio page: a button opens a modal with a form (token search, buy/sell, amount, price, date). Submissions create a `SpotTransaction`; CSV upload remains for bulk/historical. Token list is hybrid: tokens already in the user's spot account plus a static list, with type-to-search in the modal.

## Problem Statement / Motivation

- Users currently must load transactions elsewhere, export CSV, then upload here—friction for adding a single trade.
- A direct "New transaction" modal (like the other platform's UX: token search, buy/sell, amount, price, date) reduces friction while keeping CSV for flexibility.

## Proposed Solution

1. **Entry point** — "New transaction" button on spot index (e.g. next to or above the CSV upload). Only one spot account for now (default); form posts to new create action.
2. **Modal** — Same pattern as trades column picker: `<dialog>` + Stimulus `dialog` controller. Form fields: **token** (searchable select), **side** (buy/sell), **amount**, **price**, **date** (and time). No fee field.
3. **Token list (hybrid)** — Backend provides a JSON list: distinct tokens from the user's spot account's transactions, merged with a static list of common symbols. Frontend filters this list as the user types (client-side search).
4. **Create action** — New `POST spot/transactions` (or nested under spot). Params: `token`, `side`, `amount`, `price_usd`, `executed_at`. Compute `total_value_usd = amount * price_usd` and `row_signature` via `Spot::CsvRowParser.row_signature(executed_at, token, side, price_usd, amount)`. Normalize token (strip, upcase) and side (downcase). On success: redirect to `spot_path` with notice; on duplicate (row_signature exists): redirect with alert. On validation errors: re-render spot index with modal open and errors (or redirect with flash errors and reopen modal via query param—simplest is redirect back with `flash[:errors]` and a data attribute or query to reopen modal).
5. **CSV** — Unchanged; stays on the same page for bulk/historical.

## Technical Considerations

- **Routes** — Add `resources :spot_transactions, path: "spot/transactions", only: [:create], module: nil` or a single `post "spot/transactions", to: "spot#create"` with a dedicated action. Controller: `SpotController#create` (or a dedicated `SpotTransactionsController` under a scope). Prefer `SpotController#create` and `post "spot/transactions", to: "spot#create", as: :spot_transactions` for minimal new surface.
- **Token list endpoint** — Option A: inline on spot index (controller passes `@tokens_for_select = ...`). Option B: separate JSON endpoint (e.g. `GET spot/tokens`) for autocomplete. Inline is simpler: in `SpotController#index`, set `@tokens_for_select = (tokens_from_account + static_list).uniq.sort`. Frontend gets list from a data attribute or script tag (e.g. `data-controller="spot-token-select"` with `data-spot-token-select-tokens-value='<%= @tokens_for_select.to_json %>'`). No new route needed.
- **Static token list** — Define in code (e.g. `Spot::TOKEN_LIST` in `app/models/spot_transaction.rb` or `app/services/spot/`). Curated list of common symbols (BTC, ETH, SOL, USDT, etc.); keep it to a few dozen. Tokens from account: `@spot_account.spot_transactions.distinct.pluck(:token)`.
- **Row signature** — Reuse `Spot::CsvRowParser.row_signature(executed_at, token, side, price_usd, amount)`. Parse `executed_at` from params (e.g. `params[:executed_at]` as datetime string); normalize to UTC for storage and for signature.
- **Datetime** — Form sends a datetime (e.g. `datetime_local_field` → `"YYYY-MM-DDTHH:mm"`). Parse in controller with `Time.zone.parse`; store `executed_at` in UTC. For v1, document that input is interpreted in the app's default time zone (or add user timezone later). See **Research: Datetime & Timezone**.
- **Validation** — Use `SpotTransaction` validations. Build attributes in controller or a small service; set `row_signature` before save. Duplicate row_signature → redirect with alert. **Other validation errors** → do not redirect; **render :index** with same data as index plus `@spot_transaction` (with errors) and `@open_new_transaction_modal = true` so the modal reopens with field errors. See **Research: Modal + Validation Errors**.
- **Accessibility** — Modal: `<dialog>` + visible heading; trigger has `aria-label="New transaction"`. Token field: **use ARIA combobox** (not datalist) for reliable a11y and cross-browser behavior. See **Research: UI & Accessibility**.

## Acceptance Criteria

- [x] Spot index shows a "New transaction" button (when user has a spot account).
- [x] Clicking it opens a modal (native `<dialog>`) with a form: token (searchable), side (buy/sell), amount, price, date/time.
- [x] Token dropdown/list is populated with tokens from the user's spot account plus a static list; user can type to filter.
- [x] Submitting the form with valid data creates a `SpotTransaction` (correct `total_value_usd` and `row_signature`); redirect to spot index with success notice; table updates (open positions may change).
- [x] Submitting a duplicate (same executed_at, token, side, price, amount) does not create a second record; user sees an error (e.g. "This transaction already exists").
- [x] Invalid input (blank token, invalid numbers, etc.) shows validation errors (e.g. redirect back with errors and modal reopened, or inline in modal).
- [x] CSV upload still works and remains on the same page; no regression.

## Success Metrics

- User can add a single spot transaction without leaving the app or using CSV.
- Duplicate submissions are rejected; validations are clear.

## Dependencies & Risks

- **Risks:** None critical. Token static list may need occasional updates; low impact.
- **Dependencies:** None new. Reuses `Spot::CsvRowParser.row_signature`, `SpotTransaction` model, existing dialog controller.

## Performance & Security (brief)

- **Performance:** Index action adds one query for `@tokens_for_select` (distinct tokens + constant list); negligible. Create action is a single insert.
- **Security:** Use strong parameters for create; normalize token/side server-side. No new attack surface; same auth as existing spot index.

## Implementation outline

1. **Static token list** — Add `Spot::TokenList::LIST` (array of strings) in `app/services/spot/token_list.rb`; use a modest list of common symbols.
2. **SpotController#index** — Set `@tokens_for_select = (current user's spot account tokens + Spot::TokenList::LIST).uniq.sort`. Ensure spot account exists (existing `find_or_create_default_for`).
3. **Routes** — `post "spot/transactions", to: "spot#create", as: :spot_transactions`.
4. **SpotController#create** — Strong params: token, side, amount, price_usd, executed_at. Normalize token/side; parse executed_at to UTC; compute total_value_usd and row_signature; build `SpotTransaction`. **Success:** redirect to spot_path with notice. **Duplicate (uniqueness):** redirect with alert. **Validation errors:** load same data as index (`@spot_account`, `@positions`, `@current_prices`, `@tokens_for_select`), set `@spot_transaction = tx` (with errors) and `@open_new_transaction_modal = true`, then `render :index, status: :unprocessable_entity` so the modal can reopen with field errors.
5. **Spot index view** — Add "New transaction" button with `data-controller="dialog"` and `data-dialog-open-on-connect-value` when `@open_new_transaction_modal`. Add `<dialog>` with heading "New transaction" and form posting to `spot_transactions_path`. Fields: token (ARIA combobox), side select, amount number, price number, executed_at (`datetime_local_field`). Dialog controller opens modal on connect when value is true.
6. **Token search (ARIA combobox)** — Stimulus `spot_token_select_controller.js`: text input with `role="combobox"`, listbox with `role="listbox"`; filter from `tokens` value on input; ArrowUp/Down, Enter, Escape; click option to select. List populated from `@tokens_for_select`.
7. **Tests** — `SpotController` test: create with valid params creates transaction and redirects; duplicate params return error; invalid params (blank token) re-render index with 422 and modal open.

## User Flows / Edge Cases (SpecFlow)

- **Happy path:** User clicks "New transaction" → modal opens → fills token (types, selects), side, amount, price, date → Submit → transaction created, redirect to spot index, table shows updated positions.
- **Duplicate:** User submits same (executed_at, token, side, price, amount) again → backend detects existing row_signature → redirect with "This transaction already exists"; no duplicate row.
- **Validation errors:** Blank token, invalid number, or invalid date → redirect back with errors; modal can be reopened via flash so user sees errors (or show errors above form if modal reopens with params).
- **No spot account:** If for some reason user has no spot account, index already creates one via `find_or_create_default_for`; no extra handling.
- **Cancel:** User opens modal then clicks Cancel or Esc → modal closes without submitting.
- **Token not in list:** If user types a token not in hybrid list, either allow (free text) or restrict to list. Recommendation: allow any non-blank token (validate presence and format) so new symbols work without updating static list; optional: restrict to list for consistency with CSV (both approaches valid).

## Research: UI & Accessibility (Deepen)

- **Datalist vs ARIA combobox:** HTML `<datalist>` has significant accessibility and cross-browser issues: poor screen reader support (e.g. JAWS doesn't announce selected value), broken or missing support on Firefox Android, iOS 26 regression (options can obscure the input), no zoom of options, limited voice control. For production autocomplete, **prefer an ARIA combobox** (role="combobox", aria-expanded, aria-activedescendant, aria-haspopup="listbox", listbox with role="listbox" and option role="option") with keyboard (ArrowUp/Down, Enter to select, Escape to close) and proper labels. [Adrian Roselli – Under-Engineered Comboboxen; Pope Tech 2024 – accessible combobox; MDN aria-autocomplete]
- **Stimulus implementation:** Use a Stimulus controller that: (1) filters a list from `data-*-tokens-value` on input, (2) shows/hides a listbox (ul/div), (3) handles Arrow keys and Enter, (4) sets input value on select and closes list. Optionally use a small library (e.g. GitHub combobox navigation or stimulus-autocomplete) to reduce custom code; otherwise keep a minimal custom combobox (input + list + keyboard handlers). Ensure first focusable element in the modal is the token input or a visible "Add transaction" heading for a11y.
- **Modal a11y:** Native `<dialog>` already provides focus trap and Esc; give the trigger button `aria-label="New transaction"` and ensure the dialog has a visible heading (e.g. `<h2>New transaction</h2>`).

## Research: Datetime & Timezone (Deepen)

- **Rails `datetime_local_field`:** Submits a string without timezone (e.g. `"2026-03-10T14:30"`). Rails does **not** auto-interpret this as the user's local time; `Time.zone.parse` uses the app's `config.time_zone` (often UTC). To treat input as user local time you need the user's timezone (e.g. from browser via JS and a hidden field, or a user preference). **Simpler for v1:** Treat submitted datetime as **server time** (or document "enter in UTC") and parse with `Time.zone.parse(params[:executed_at])` then store in DB as UTC. If the app already has a user timezone setting, use it when parsing so "3pm" is 3pm in their zone. [Rails datetime form timezone SO; store UTC best practice]
- **Storage:** Keep storing `executed_at` in UTC in the DB; no schema change. Normalize to UTC before calling `CsvRowParser.row_signature` so duplicate detection is consistent.

## Research: Modal + Validation Errors (Deepen)

- **Redirect loses errors:** If `create` uses `redirect_to spot_path` on validation failure, the model errors are lost and the modal won't show field-level errors. **Recommended:** On validation failure, **render the index** instead of redirecting: `render :index, status: :unprocessable_entity`, after setting the same instance variables as `index` (`@spot_account`, `@positions`, `@current_prices`, `@tokens_for_select`) plus a failed `@spot_transaction` (or `@transaction`) and a flag like `@open_new_transaction_modal = true`. The view (or a small Stimulus controller) checks for that flag on load and calls `dialogTarget.showModal()`. Form then displays `@spot_transaction.errors` next to each field. On success, keep using `redirect_to spot_path, notice: "..."`. [SO: keep modal open with validation errors; render vs redirect]
- **Duplicate row_signature:** Still use redirect with `flash[:alert]` (no need to re-render the form for a duplicate).

## References & Research

- **Modal pattern:** `app/views/trades/index.html.erb` (Columns button + dialog), `app/javascript/controllers/dialog_controller.js`
- **Spot transaction model:** `app/models/spot_transaction.rb`, `app/services/spot/csv_row_parser.rb` (row_signature)
- **Spot controller/index:** `app/controllers/spot_controller.rb`, `app/views/spot/index.html.erb`
- **Existing plan (modal):** `docs/plans/2026-03-06-feat-trades-index-columns-configurable-plan.md` (dialog + form + redirect)
- **External (deepen):** Adrian Roselli – [Under-Engineered Comboboxen](https://adrianroselli.com/2023/06/under-engineered-comboboxen.html); Pope Tech – [Accessible combobox with ARIA](https://blog.pope.tech/2024/07/01/create-an-accessible-combobox-using-aria/); Rails datetime timezone (SO); SO – keep modal open on validation error
