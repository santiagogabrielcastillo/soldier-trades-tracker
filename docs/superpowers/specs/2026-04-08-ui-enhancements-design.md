# UI Enhancements: Settings AI Key + Global Money Visibility Toggle

## Goal

Two independent UI improvements: (1) redesign the AI key settings section into a proper feature card and fix cursor-pointer globally, and (2) extract the stocks-only money visibility toggle into a platform-wide feature accessible from the navbar.

## Architecture

Two loosely coupled changes. The cursor fix is a single CSS rule. The settings redesign touches one view file. The money toggle involves modifying two Ruby helpers, creating one Stimulus controller, updating the layout, and removing the now-superseded stocks-specific controller.

## Tech Stack

Rails 7.2, Tailwind CSS, Stimulus (Hotwire), importmap-rails, localStorage for toggle persistence.

---

## Feature 1: cursor-pointer + Settings AI Key Redesign

### cursor-pointer

Add one rule to `app/assets/stylesheets/application.css` inside `@layer base`:

```css
button { cursor: pointer; }
```

This applies globally to every `<button>` element across the entire app, including Turbo-rendered and Stimulus-connected buttons.

### Settings AI Key Card

File: `app/views/settings/show.html.erb` — the existing AI Assistant fieldset.

**Card structure:**

- **Header row:** lock SVG icon + "AI Assistant" bold title + subtle "Powered by Gemini" text on the right
- **Description line:** "Connect your free Gemini API key to enable AI-powered portfolio analysis." followed by an anchor — "Get a free key at aistudio.google.com" — with `target="_blank" rel="noopener noreferrer"`

**Unconfigured state (`unless current_user.gemini_api_key_configured?`):**

- Flex row: full-width text input (placeholder `AIza...`, `name="api_key"`, `autocomplete="off"`) + "Save" button inline to the right
- Small muted hint below the row: "Your key is stored encrypted and never shared."
- Form POSTs to `settings_ai_key_path` with `method: :patch`

**Configured state:**

- Key display row: monospace masked key (`current_user.gemini_api_key_masked`) with a green dot + "Active" badge to its right
- Button row below: "Test Connection" button (slate primary) + "Remove" link-button (red ghost text, DELETE to `remove_settings_ai_key_path`)
- Inline result span with `data-ai-settings-target="result"` for test connection feedback (no change to Stimulus wiring)

The entire card uses the same border/bg/padding pattern as the existing sync interval card on the page (`rounded-lg border border-slate-200 bg-white p-4`).

---

## Feature 2: Global Money Visibility Toggle

### Helper changes — `app/helpers/application_helper.rb`

`format_money` and `format_ars` currently return a plain string. They will be updated to return an HTML-safe string wrapping real values in `<span data-money>`:

```ruby
def format_money(amount)
  return "—" if amount.nil?
  content_tag(:span, number_to_currency(amount, unit: "$", delimiter: ",", precision: 2),
              class: "font-numeric", data: { money: true })
end

def format_ars(amount)
  return "—" if amount.nil?
  content_tag(:span, number_to_currency(amount, unit: "ARS ", delimiter: ".", precision: 0),
              class: "font-numeric", data: { money: true })
end
```

Nil returns (`"—"`) are plain strings with no `data-money` — there is nothing to mask.

Any view using these helpers automatically becomes maskable with no individual view changes needed.

### `money_visibility_controller.js` — `app/javascript/controllers/money_visibility_controller.js`

A new Stimulus controller attached to `<body>` in the application layout.

```
static targets = ["eyeOn", "eyeOff"]
static STORAGE_KEY = "money_hidden"
static MASK = '<span class="font-numeric text-slate-300 select-none">*</span>'
```

**`connect()`:** Called on every page load and Turbo navigation. Reads `localStorage["money_hidden"]` and calls `#applyVisibility`.

**`toggle()`:** Flips the stored boolean, calls `#applyVisibility`.

**`#applyVisibility(hidden)`:**
- Iterates `document.querySelectorAll('[data-money]')`
- When hiding: saves `el.innerHTML` to `el.dataset.originalContent`, sets `el.innerHTML = MASK`
- When showing: restores `el.innerHTML` from `el.dataset.originalContent`, deletes the attribute
- Toggles `hidden` class on `eyeOnTarget` and `eyeOffTarget`

The controller is attached to `<body>`, so it wraps all page content and can reach every `[data-money]` element regardless of page. On Turbo navigation, Stimulus disconnects and reconnects the controller automatically, re-running `connect()` on each new page.

### Navbar button — `app/views/layouts/application.html.erb`

The toggle button is added in two places, both wired to `data-action="click->money-visibility#toggle"` on the `<body>` controller. Because Stimulus actions can reference ancestor controllers, the buttons don't need to be inside the controller element — they just need the `data-action` attribute pointing at `money-visibility#toggle`.

**Desktop sidebar:** A button in the footer section of the sidebar (below the Settings link, above the Sign out button), styled as an icon button matching the sidebar's icon links. Contains two SVG children: eye-open (`data-money-visibility-target="eyeOn"`) and eye-closed (`data-money-visibility-target="eyeOff"`), toggled via `hidden` class.

**Mobile header:** The same icon button (same targets, same action) added to the right side of the top sticky header, next to the existing hamburger button.

Initial HTML state matches what `connect()` would render — if `money_hidden` is `"true"` in storage, the eye-closed icon is shown by default via the server-rendered HTML. Since we can't read localStorage server-side, both buttons render with eye-open visible and eye-closed hidden; `connect()` corrects this immediately on load.

### Stocks controller removal

- `app/javascript/controllers/stocks_table_controller.js` — delete the file entirely
- `app/views/stocks/index.html.erb` — remove `data-controller="stocks-table"` binding, remove the eye toggle button (with `eyeOn`/`eyeOff` SVGs), remove all `data-stocks-table-target="moneyCell"` attributes from money cells (they are now covered by `data-money` from the helpers)

The localStorage key `stocks_table_amounts_hidden` is superseded by `money_hidden`. No migration needed — old values simply expire.

---

## Testing

### cursor-pointer
No automated test — visual verification.

### Settings view
Existing controller tests in `test/controllers/settings_controller_test.rb` cover the actions. Add/update view assertions:
- Unconfigured: `assert_select "input[name='api_key']"` and `assert_match "aistudio.google.com", response.body`
- Configured: `assert_match @user.gemini_api_key_masked, response.body` and `assert_select "button", text: "Test Connection"`

### format_money / format_ars helpers
Add unit tests in `test/helpers/application_helper_test.rb`:
- `format_money(nil)` returns `"—"` (plain string, no span)
- `format_money(1234.56)` returns HTML containing `data-money` and `$1,234.56`
- `format_ars(nil)` returns `"—"`
- `format_ars(5000)` returns HTML containing `data-money` and `ARS 5.000`

### money_visibility_controller
No unit tests for Stimulus controllers in this codebase. Run full test suite to verify no regressions.

### Stocks controller removal
Run `bin/rails test` to confirm no references to the removed controller remain.
