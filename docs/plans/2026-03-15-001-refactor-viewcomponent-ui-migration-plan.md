---
title: Migrate UI to ViewComponent primitive-first hierarchy
type: refactor
status: active
date: 2026-03-15
origin: docs/brainstorms/2026-03-15-viewcomponent-migration-brainstorm.md
---

# Migrate UI to ViewComponent Primitive-First Hierarchy

## Overview

Install the `view_component` gem and extract ~10 highly-duplicated UI patterns from ~18 view files into a three-layer component hierarchy (primitives → composites → page-level). All existing views are refactored in a single pass. Tests are a separate phase 2 effort.

Driven by: stop duplication, lay a testability foundation, enforce design consistency.

---

## Enhancement Summary

**Deepened on:** 2026-03-15  
**Sections enhanced:** Installation & Configuration, Component Hierarchy, pl_color_class, Implementation Phases, System-Wide Impact, Dependencies & Risks  
**Research agents used:** framework-docs-researcher, best-practices-researcher, explore, architecture-strategist, kieran-rails-reviewer, code-simplicity-reviewer, performance-oracle, pattern-recognition-specialist, security-sentinel, julik-frontend-races-reviewer  
**Documentation:** Context7 (ViewComponent), web search (ViewComponent 3.x, Tailwind v4)

### Key Improvements

1. **Gem version:** Pin to `~> 3.22` (avoid 3.21.0; [regression](https://github.com/ViewComponent/view_component/issues/2187) in `render_inline` fixed in 3.22).
2. **Single source for `pl_color_class`:** Define once in `ApplicationHelper`; have `ApplicationComponent` call `helpers.pl_color_class(value)` — no duplicate logic.
3. **ButtonComponent:** Merge caller `class` with variant (e.g. `class: [VARIANTS.fetch(variant), html_options[:class]].compact.join(" ")`) so callers can add extra classes; optionally normalize `html_options.symbolize_keys` for string-keyed options from Modal.
4. **ModalComponent:** Add optional `open_on_connect: false` and render `data-dialog-open-on-connect-value="true"` when set so validation-error re-renders keep the modal open (spot/stocks pattern).
5. **DateRangeFilterComponent:** Add `data: { auto_submit_form_target: "trigger" }` to both date inputs so the existing `auto-submit-form` Stimulus controller has targets and the form auto-submits on date change.
6. **DataTableComponent:** Use string reference for nested slot — `renders_many :rows, "RowComponent"` — and place `row_component.html.erb` under `data_table_component/` to avoid load-order issues.
7. **Security & robustness:** Validate FormField `type` (`:text` / `:password` only); use `VARIANTS.fetch(variant)` in Badge so invalid variants raise; treat `DateRangeFilterComponent#extra_params` as allowlist-only in controllers.
8. **Phases:** Run RuboCop on `app/components/` at end of Phase 4 (PR 1); remove duplicate "add pl_color_class" from Phase 5 (helper is added in Phase 1).

### New Considerations Discovered

- **Nil P&L color scope:** Plan uses `text-slate-900` for nil (dashboard stat context). Table cells in spot/stocks/trades currently use `text-slate-500` for nil — document that `pl_color_class` is for stat/summary only; table-cell nil styling stays out of scope or is handled in phase 2 via TradeCellComponent.
- **POST actions (e.g. Sync now, Set as default):** Plan covers link/button with `href` + `method: :delete`. Document that POST `button_to` actions remain in views and are not migrated to ButtonComponent unless the component is extended for form+submit.
- **Optional simplifications (YAGNI):** Consider dropping Card `padding: :large`, Modal `trigger_variant`, and StatCard `size` until a view needs them; or implement StatCard `size` in `value_css` if dashboard uses both text sizes.

---

## Problem Statement

The view layer has zero component abstractions — one partial in the entire codebase. Repeated patterns are copy-pasted verbatim:

- **Button class strings** (80+ chars) appear in every view and helper
- **Stat card** label+value pattern repeated ~20 times across dashboard, spot, stocks
- **Tab navigation** copied character-for-character across 3 pages
- **Modal dialog** structure copy-pasted between spot and stocks
- **Date range filter** form near-identical across trades, spot, and stocks
- **Data table** wrapper duplicated 3 times
- **Error summary**, **empty state**, and **P&L color ternary** each repeated 3–12 times

A change to any of these patterns requires touching multiple files. There is no single source of truth.

---

## Proposed Solution

Install `view_component` ~> 3.x and build a component hierarchy in dependency order. Tailwind utility classes stay inline inside component templates. Stimulus `data-*` attributes are preserved exactly. Tests are a phase 2 addition.

**Two-PR delivery** (within the big-bang strategy) to reduce regression surface:
- **PR 1**: Gem installation + `ApplicationComponent` base + all component classes with templates (not yet used in any views)
- **PR 2**: Replace all 18 view files to use the new components

---

## Technical Approach

### Installation & Configuration

**Step 1 — Gemfile**
```ruby
# Gemfile
gem "view_component", "~> 3.22"
```
Run `bundle install`. Verify `ViewComponent::Base` is available. Use 3.22+ (3.21.0 had a [render_inline regression](https://github.com/ViewComponent/view_component/issues/2187) fixed in 3.22.0).

**Step 2 — Tailwind content scanning**

The project uses Tailwind CSS v4 via `tailwindcss-rails`. In v4, the oxide engine auto-scans the project. Verify it picks up `app/components/` by adding one component with a unique Tailwind class (e.g., a never-before-used `bg-teal-300`), running `bin/rails tailwindcss:build`, and confirming the class appears in the output CSS.

If v4 auto-detection misses the directory (check with `grep -r "teal-300" app/assets/builds/`), add an explicit source directive to `app/assets/tailwind/application.css`:
```css
@source "../../app/components";
```

**Step 3 — No `application.rb` changes needed**

`app/components/` is auto-discovered by Zeitwerk in Rails 7.2. No `config.autoload_paths` changes required.

**Step 4 — Base component class**

```ruby
# app/components/application_component.rb
# frozen_string_literal: true

class ApplicationComponent < ViewComponent::Base
  include ApplicationHelper

  private

  # Single source of truth: implemented in ApplicationHelper; component calls helper.
  # Nil → text-slate-900 (stat/summary); zero treated as non-negative (green).
  def pl_color_class(value)
    helpers.pl_color_class(value)
  end
end
```

`ApplicationHelper` includes only `format_money` and `interval_hint` — both pure computational methods with no controller dependency, safe to include directly.

**Research insight — single source for pl_color_class:** Define `pl_color_class` only in `ApplicationHelper`. In `ApplicationComponent`, call `helpers.pl_color_class(value)` (or a private wrapper) instead of duplicating the logic; remove the private method from the base class so there is one source of truth.

---

### Component Hierarchy

#### Layer 1 — Primitives

**`ButtonComponent`**

Renders a `<button>` or `<a>` depending on whether `href:` is provided. Accepts `**html_options` passthrough to support `data-turbo-confirm`, `method: :delete`, `form:` attributes used in the existing exchange account and portfolio delete flows.

```ruby
# app/components/button_component.rb
# frozen_string_literal: true

class ButtonComponent < ApplicationComponent
  VARIANTS = {
    primary: "rounded-md bg-slate-800 px-4 py-2 text-sm font-medium text-white hover:bg-slate-700 focus:outline-none focus:ring-2 focus:ring-slate-500",
    secondary: "rounded-md border border-slate-300 bg-white px-4 py-2 text-sm font-medium text-slate-700 hover:bg-slate-50"
  }.freeze

  def initialize(label:, variant: :primary, href: nil, **html_options)
    @label = label
    @variant = variant
    @href = href
    base_class = VARIANTS.fetch(variant)
    merged_class = [base_class, html_options[:class]].compact.join(" ")
    @html_options = html_options.except(:class).merge(class: merged_class).symbolize_keys
  end
end
```

**Research insight:** Merge variant and caller `class` so callers can add extra classes (e.g. `class: "mt-4"`). Use `symbolize_keys` so string-keyed options (e.g. from Modal’s `"data-action"`) work with `tag.attributes`. For the button branch, `button_tag @label, **@html_options` is an idiomatic alternative to raw `<button>`.

Template (`button_component.html.erb`):
```erb
<% if @href %>
  <%= link_to @label, @href, **@html_options %>
<% else %>
  <button <%= tag.attributes(**@html_options) %>><%= @label %></button>
<% end %>
```

**`BadgeComponent`**

```ruby
# app/components/badge_component.rb
# frozen_string_literal: true

class BadgeComponent < ApplicationComponent
  VARIANTS = {
    default: "rounded bg-slate-100 px-2 py-0.5 text-xs font-medium text-slate-600",
    success: "rounded bg-emerald-100 px-2 py-0.5 text-xs font-medium text-emerald-700",
    warning: "rounded bg-amber-100 px-2 py-0.5 text-xs font-medium text-amber-700",
    danger:  "rounded bg-red-100 px-2 py-0.5 text-xs font-medium text-red-700"
  }.freeze

  def initialize(label:, variant: :default)
    @label = label
    @variant = variant
    @variant_css = VARIANTS.fetch(variant)  # resolve in component; invalid variant raises
  end
end
```

Template:
```erb
<span class="<%= @variant_css %>"><%= @label %></span>
```

**`CardComponent`**

```ruby
# app/components/card_component.rb
# frozen_string_literal: true

class CardComponent < ApplicationComponent
  def initialize(heading: nil, padding: :default)
    @heading = heading
    @padding = padding == :large ? "p-8" : "p-6"
  end
end
```

Template:
```erb
<section class="rounded-lg border border-slate-200 bg-white <%= @padding %> shadow-sm">
  <% if @heading %>
    <h2 class="mb-4 text-lg font-semibold text-slate-800"><%= @heading %></h2>
  <% end %>
  <%= content %>
</section>
```

---

#### Layer 2 — Composites

**`StatCardComponent`**

Replaces ~20 repetitions of the label+value pair. Handles nil values and optional P&L coloring.

```ruby
# app/components/stat_card_component.rb
# frozen_string_literal: true

class StatCardComponent < ApplicationComponent
  def initialize(label:, value:, signed: false, size: :default)
    @label = label
    @value = value
    @signed = signed
    @size = size
  end

  def value_css
    return "text-xl font-semibold text-slate-900" unless @signed

    "text-xl font-semibold #{pl_color_class(@value)}"
  end

  def display_value
    @value.nil? ? "—" : @value
  end
end
```

Template:
```erb
<div>
  <span class="text-sm text-slate-500"><%= @label %></span>
  <p class="<%= value_css %>"><%= display_value %></p>
</div>
```

**`FormFieldComponent`**

Covers `type: :text` and `type: :password` only. Select and date fields remain inline in this phase.

```ruby
# app/components/form_field_component.rb
# frozen_string_literal: true

class FormFieldComponent < ApplicationComponent
  INPUT_CLASSES = "mt-1 block w-full rounded-md border border-slate-300 px-3 py-2 shadow-sm focus:border-slate-500 focus:outline-none focus:ring-1 focus:ring-slate-500".freeze

  def initialize(form:, attribute:, label:, type: :text, required: false)
    raise ArgumentError, "type must be :text or :password" unless %i[text password].include?(type)
    @form = form
    @attribute = attribute
    @label = label
    @type = type
    @required = required
  end
end
```

Template:
```erb
<div>
  <%= @form.label @attribute, @label, class: "block text-sm font-medium text-slate-700" %>
  <%= @form.send(:"#{@type}_field", @attribute, class: INPUT_CLASSES, required: @required) %>
</div>
```

**`ErrorSummaryComponent`**

```ruby
# app/components/error_summary_component.rb
# frozen_string_literal: true

class ErrorSummaryComponent < ApplicationComponent
  def initialize(model:)
    @model = model
  end

  def render?
    @model.errors.any?
  end
end
```

Template:
```erb
<div class="rounded-md bg-amber-50 p-4 text-sm text-amber-800">
  <ul class="list-disc pl-5">
    <% @model.errors.full_messages.each do |msg| %>
      <li><%= msg %></li>
    <% end %>
  </ul>
</div>
```

**`InlineFieldErrorComponent`**

```ruby
# app/components/inline_field_error_component.rb
# frozen_string_literal: true

class InlineFieldErrorComponent < ApplicationComponent
  def initialize(errors:, attribute:)
    @errors = errors
    @attribute = attribute
  end

  def render?
    @errors[@attribute].any?
  end
end
```

Template:
```erb
<p class="mt-1 text-sm text-red-600"><%= @errors[@attribute].first %></p>
```

**`EmptyStateComponent`**

```ruby
# app/components/empty_state_component.rb
# frozen_string_literal: true

class EmptyStateComponent < ApplicationComponent
  def initialize(message:)
    @message = message
  end
end
```

Template:
```erb
<div class="rounded-lg border border-slate-200 bg-white p-12 text-center text-slate-600">
  <p><%= @message %></p>
  <% if content? %>
    <div class="mt-4"><%= content %></div>
  <% end %>
</div>
```

**`TabNavComponent`**

Active state is computed by the call site (view/controller), passed in as a boolean per tab. This avoids the component needing `request.path` access.

```ruby
# app/components/tab_nav_component.rb
# frozen_string_literal: true

class TabNavComponent < ApplicationComponent
  Tab = Data.define(:label, :url, :active)

  def initialize(tabs:)
    @tabs = tabs.map { Tab.new(**_1.transform_keys(&:to_sym)) }
  end

  def tab_css(active)
    base = "border-b-2 px-4 py-2 text-sm font-medium"
    if active
      "#{base} border-slate-800 text-slate-900"
    else
      "#{base} border-transparent text-slate-500 hover:border-slate-300 hover:text-slate-700"
    end
  end
end
```

Template:
```erb
<nav class="mb-6 flex gap-1 border-b border-slate-200">
  <% @tabs.each do |tab| %>
    <%= link_to tab.label, tab.url, class: tab_css(tab.active) %>
  <% end %>
</nav>
```

---

#### Layer 3 — Page-Level

**`DateRangeFilterComponent`**

Owns the `<form>` tag. `data: { turbo: false }` is baked in — this matches the project-wide convention and prevents silent Turbo Drive takeover of GET filter forms.

```ruby
# app/components/date_range_filter_component.rb
# frozen_string_literal: true

class DateRangeFilterComponent < ApplicationComponent
  DATE_FIELD_CLASSES = "mt-1 block rounded-md border border-slate-300 px-3 py-2 text-sm shadow-sm focus:border-slate-500 focus:outline-none focus:ring-1 focus:ring-slate-500".freeze

  def initialize(url:, from:, to:, extra_params: {})
    @url = url
    @from = from
    @to = to
    @extra_params = extra_params
  end
end
```

Template:
```erb
<%# Shared constant for date input classes to avoid duplication %>
<%= form_with url: @url, method: :get, data: { turbo: false, controller: "auto-submit-form" }, class: "flex flex-wrap items-end gap-4" do |f| %>
  <div>
    <%= f.label :from, "From", class: "block text-sm font-medium text-slate-700" %>
    <%= f.date_field :from, value: @from, class: DateRangeFilterComponent::DATE_FIELD_CLASSES, data: { auto_submit_form_target: "trigger" } %>
  </div>
  <div>
    <%= f.label :to, "To", class: "block text-sm font-medium text-slate-700" %>
    <%= f.date_field :to, value: @to, class: DateRangeFilterComponent::DATE_FIELD_CLASSES, data: { auto_submit_form_target: "trigger" } %>
  </div>
  <% @extra_params.each do |name, value| %>
    <%= hidden_field_tag name, value %>
  <% end %>
<% end %>
```
**Research insight:** The existing `auto_submit_form_controller.js` binds `change` to `this.triggerTargets`; add `data: { auto_submit_form_target: "trigger" }` to both date inputs so the form auto-submits on date change. Controllers must build `extra_params` from an allowlist only (e.g. `view`, `exchange_account_id`, `portfolio_id`) — never from raw params.

**`DataTableComponent`**

Uses `renders_many :rows` slot. The component owns the wrapper + `<thead>` structure; callers provide row HTML via the slot.

```ruby
# app/components/data_table_component.rb
# frozen_string_literal: true

class DataTableComponent < ApplicationComponent
  # Use string "RowComponent" so ViewComponent resolves nested class correctly (avoids load-order issues).
  renders_many :rows, "RowComponent"

  def initialize(columns:)
    @columns = columns  # Array of { label: String, classes: String (optional) }
  end

  class RowComponent < ViewComponent::Base
    def initialize(classes: "")
      @classes = classes
    end
  end
end
```

Template (`data_table_component.html.erb`):
```erb
<div class="overflow-x-auto rounded-lg border border-slate-200 bg-white shadow-sm">
  <table class="min-w-full divide-y divide-slate-200">
    <thead class="bg-slate-50">
      <tr>
        <% @columns.each do |col| %>
          <th class="px-6 py-3 text-left text-xs font-medium uppercase tracking-wider text-slate-600 <%= col[:classes] %>">
            <%= col[:label] %>
          </th>
        <% end %>
      </tr>
    </thead>
    <tbody class="divide-y divide-slate-200 bg-white">
      <%= rows %>
    </tbody>
  </table>
</div>
```

Template (`data_table_component/row_component.html.erb`): place under parent directory so ViewComponent finds it. Call site: `component.with_row(classes: "...") { ... }` — block outputs `<td>...</td>` content.

**`ModalComponent`**

Uses the **existing** `dialog` Stimulus controller (`app/javascript/controllers/dialog_controller.js`). No new JS required. Preserves the `data-controller="dialog"` / `data-dialog-target="dialog"` wiring exactly.

```ruby
# app/components/modal_component.rb
# frozen_string_literal: true

class ModalComponent < ApplicationComponent
  def initialize(title:, trigger_label:, trigger_variant: :primary, open_on_connect: false)
    @title = title
    @trigger_label = trigger_label
    @trigger_variant = trigger_variant
    @open_on_connect = open_on_connect
  end
end
```

**Research insight:** Spot/stocks pass `data-dialog-open-on-connect-value="true"` when re-rendering after a validation error so the modal stays open. Add optional `open_on_connect:` and render `data-dialog-open-on-connect-value="true"` on the wrapper `div` when set.

Template:
```erb
<div data-controller="dialog"<%= ' data-dialog-open-on-connect-value="true"' if @open_on_connect %>>
  <%= render ButtonComponent.new(
        label: @trigger_label,
        variant: @trigger_variant,
        **{ "data-action": "click->dialog#open" }
      ) %>

  <dialog data-dialog-target="dialog" class="rounded-lg border border-slate-200 bg-white p-6 shadow-lg backdrop:bg-slate-900/50">
    <div class="mb-4 flex items-center justify-between">
      <h2 class="text-lg font-semibold text-slate-800"><%= @title %></h2>
      <button type="button" data-action="click->dialog#close"
              class="rounded p-1 text-slate-400 hover:bg-slate-100 hover:text-slate-600">✕</button>
    </div>
    <%= content %>
  </dialog>
</div>
```

---

### pl_color_class Helper Extraction

**Single source of truth:** Define `pl_color_class` only in `ApplicationHelper`. In `ApplicationComponent`, call `helpers.pl_color_class(value)` (remove the private method from the base class).

```ruby
# app/helpers/application_helper.rb (add to existing file)
def pl_color_class(value)
  return "text-slate-900" if value.nil?
  value >= 0 ? "text-emerald-600" : "text-red-600"
end
```

This unifies the ~12 inline ternaries plus the `trades_index_cell_css` helper into one definition. The nil-guard maps to `text-slate-900` (matching the existing dashboard nil variant on lines 19 and 23 of `dashboards/show.html.erb`).

**Research insight — nil scope:** Use `pl_color_class` for **stat/summary** contexts (dashboard cards); nil → `text-slate-900`. Table cells in spot/stocks/trades currently use `text-slate-500` for nil — keep that behavior out of scope for this phase (or handle in phase 2 via TradeCellComponent) so replacing ternaries doesn’t change table appearance.

---

### View Files in Scope (All 18)

| File | Components Used |
|---|---|
| `layouts/application.html.erb` | `ButtonComponent` (nav links if applicable) |
| `dashboards/show.html.erb` | `CardComponent`, `StatCardComponent`, `TabNavComponent` |
| `trades/index.html.erb` | `CardComponent`, `TabNavComponent`, `DateRangeFilterComponent`, `DataTableComponent`, `EmptyStateComponent` |
| `spot/index.html.erb` | `CardComponent`, `TabNavComponent`, `StatCardComponent`, `DateRangeFilterComponent`, `DataTableComponent`, `ModalComponent`, `EmptyStateComponent` |
| `stocks/index.html.erb` | Same as spot |
| `portfolios/index.html.erb` | `CardComponent`, `BadgeComponent`, `ButtonComponent`, `EmptyStateComponent` |
| `portfolios/_form.html.erb` | `FormFieldComponent`, `ErrorSummaryComponent` |
| `portfolios/new.html.erb` | No change (renders partial) |
| `portfolios/edit.html.erb` | No change (renders partial) |
| `exchange_accounts/index.html.erb` | `CardComponent`, `ButtonComponent`, `EmptyStateComponent` |
| `exchange_accounts/new.html.erb` | `CardComponent`, `FormFieldComponent`, `ErrorSummaryComponent`, `ButtonComponent` |
| `sessions/new.html.erb` | `CardComponent`, `FormFieldComponent`, `ErrorSummaryComponent`, `ButtonComponent` |
| `users/new.html.erb` | `CardComponent`, `FormFieldComponent`, `ErrorSummaryComponent`, `ButtonComponent` |
| `settings/show.html.erb` | `CardComponent`, `ButtonComponent` |
| `pwa/manifest.json.erb` | No change (JSON, no UI) |
| `pwa/service-worker.js` | No change (JS, no UI) |
| `layouts/mailer.html.erb` | No change (email layout, separate visual language) |
| `layouts/mailer.text.erb` | No change |

---

### Known Gaps & Phase Boundaries

| Gap | Decision |
|---|---|
| `FormFieldComponent` for `type: :select` and `type: :date` | Deferred to phase 2. These fields remain as inline ERB in portfolio forms and exchange account forms. |
| `TradeCellComponent` (extract `trades_index_cell_content`/`css` helpers) | Deferred to phase 2. The helpers are already reasonably contained. |
| ViewComponent unit tests | Phase 2. `ViewComponent::TestCase` integrates with Minitest natively — no extra setup beyond the gem. |
| Component previews | Phase 2. `ApplicationComponent` base class does not block preview support. |
| `app/components/` directory structure | Flat for now. Subdirectory extraction (`primitives/`, `composites/`) when component count warrants it. |

---

## Implementation Phases

### Phase 1 — Setup (PR 1 start)

- [ ] Add `gem "view_component", "~> 3.22"` to Gemfile, run `bundle install`
- [ ] Create `app/components/` directory
- [ ] Write `app/components/application_component.rb` with `include ApplicationHelper` and call `helpers.pl_color_class(value)` (no private duplicate)
- [ ] Add `pl_color_class` to `app/helpers/application_helper.rb`
- [ ] Verify Tailwind v4 scans `app/components/` (smoke test with a unique class)
- [ ] Run existing test suite — `bin/rails test` — confirm green

### Phase 2 — Layer 1: Primitives (PR 1 continued)

- [ ] `app/components/button_component.rb` + template
- [ ] `app/components/badge_component.rb` + template
- [ ] `app/components/card_component.rb` + template
- [ ] Run test suite

### Phase 3 — Layer 2: Composites (PR 1 continued)

- [ ] `app/components/stat_card_component.rb` + template
- [ ] `app/components/form_field_component.rb` + template
- [ ] `app/components/error_summary_component.rb` + template
- [ ] `app/components/inline_field_error_component.rb` + template
- [ ] `app/components/empty_state_component.rb` + template
- [ ] `app/components/tab_nav_component.rb` + template
- [ ] Run test suite

### Phase 4 — Layer 3: Page-Level (PR 1 concluded)

- [ ] `app/components/date_range_filter_component.rb` + template
- [ ] `app/components/data_table_component.rb` + templates (including `row_component`)
- [ ] `app/components/modal_component.rb` + template
- [ ] Run test suite, open app in browser and verify no errors (components exist but are unused — app should behave identically at this point)
- [ ] Run `bundle exec rubocop -a` on `app/components/` (so PR 1 settles component style; PR 2 is view-only)
- [ ] **Merge PR 1**

### Phase 5 — View Migration (PR 2)

Replace all 18 view files in the dependency order from Phase 2 table (do not re-add `pl_color_class` to the helper — it is added in Phase 1):

- [ ] `app/views/layouts/application.html.erb`
- [ ] `app/views/sessions/new.html.erb` and `users/new.html.erb` (simplest forms)
- [ ] `app/views/exchange_accounts/new.html.erb` and `index.html.erb`
- [ ] `app/views/portfolios/_form.html.erb`, `index.html.erb`
- [ ] `app/views/settings/show.html.erb`
- [ ] `app/views/dashboards/show.html.erb`
- [ ] `app/views/trades/index.html.erb`
- [ ] `app/views/spot/index.html.erb`
- [ ] `app/views/stocks/index.html.erb`

### Phase 6 — Cleanup (PR 2 concluded)

- [ ] Delete or simplify now-redundant helpers: `spot_index_filter_params`, `stocks_index_filter_params` (superseded by `DateRangeFilterComponent#extra_params`)
- [ ] Run `bundle exec rubocop -a` on new component files
- [ ] Run full test suite — `bin/rails test`
- [ ] Manual smoke-test checklist (see Acceptance Criteria)
- [ ] **Merge PR 2**

---

## Alternative Approaches Considered

| Approach | Why Rejected |
|---|---|
| **Helpers for atoms, components for composites** | Mixed paradigm — some things in helpers, others in components. Inconsistent mental model. Buttons-as-helpers remain untestable. |
| **Top 5 patterns only (no DataTable/Modal/TabNav)** | Still leaves significant copy-paste across 3 pages. Doesn't solve the consistency problem fully. |
| **Incremental (new code first)** | Deferred benefit — duplication continues accumulating while waiting for new feature opportunities. |

---

## System-Wide Impact

### Interaction Graph

ViewComponent is purely server-side rendering — no controller action changes. The chain is:
`Request → Controller → assigns instance vars → View renders components → Response`

Components call `helpers.*` for view helpers (format_money, url helpers). No callbacks, no middleware changes.

### Error Propagation

Components raise `ArgumentError` at initialization if required keyword args are missing. These surface as 500 errors in development with a clear stack trace pointing to the caller view. This is stricter than the current silent nil-rendering in ERB — a good thing.

`render?` returning false causes the component to render nothing (used in `ErrorSummaryComponent`, `InlineFieldErrorComponent`). No error is raised.

### State Lifecycle Risks

Components are stateless — they hold no instance variables between requests. Each `render` initializes fresh. No persistence, no cache, no background state.

### API Surface Parity

- **Trades helper** (`trades_index_cell_content`, `trades_index_cell_css`) is not replaced in this phase — it's still called from `trades/index.html.erb` which will use `DataTableComponent` for the wrapper but still delegate cell content to the helper. Clean extraction deferred to phase 2 `TradeCellComponent`.
- **`format_money` helper** remains in `ApplicationHelper` and is callable from components via the `include ApplicationHelper` in `ApplicationComponent`.

### Security (research)

- **DateRangeFilterComponent `extra_params`:** Build from an allowlist in controllers (e.g. `view`, `exchange_account_id`, `portfolio_id`); never from raw params to avoid parameter injection.
- **ButtonComponent `html_options`:** Document that `html_options` must not be derived from user or request input; use fixed literals or server-controlled config. Optional: allowlist keys (e.g. `%i[method form class data rel aria]`) in the component.
- **ErrorSummary / InlineFieldError:** Keep using `<%= %>` for messages (Rails escapes); do not use `raw` or `.html_safe` for error or modal content.

### Frontend (Stimulus) — required fixes

- **ModalComponent:** Support `open_on_connect: true` and render `data-dialog-open-on-connect-value="true"` on the wrapper so validation-error re-renders (spot/stocks) keep the modal open.
- **DateRangeFilterComponent:** Add `data: { auto_submit_form_target: "trigger" }` to both date inputs so the existing `auto-submit-form` controller has targets and the form auto-submits on date change.

### Integration Test Scenarios

1. Dashboard stat cards render with real position data — P&L coloring correct for positive/negative/nil values
2. Tab navigation active state is correct on initial load (spot portfolio tab, transactions tab)
3. Date range filter form submits as GET (not Turbo), URL params update, table re-renders filtered results
4. New transaction modal opens, form validation error shows `InlineFieldErrorComponent`, closes without losing unsaved data
5. Exchange account create with validation error shows `ErrorSummaryComponent`, form retains filled values

---

## Acceptance Criteria

### Functional Requirements

- [ ] All 18 view files render without errors in development
- [ ] `ButtonComponent` renders `<button>` or `<a>` correctly; supports `method: :delete` and `data-turbo-confirm` via `**html_options`
- [ ] `BadgeComponent` renders with all 4 variants
- [ ] `CardComponent` renders with and without `heading:`; content is yielded
- [ ] `StatCardComponent` renders "—" for nil values; applies P&L color when `signed: true`
- [ ] `TabNavComponent` applies correct active/inactive CSS classes
- [ ] `DateRangeFilterComponent` renders a GET form with `data-controller="auto-submit-form"` and `data: { turbo: false }` — confirmed by inspecting rendered HTML
- [ ] `ModalComponent` opens and closes via existing `dialog` Stimulus controller without JS changes
- [ ] `ErrorSummaryComponent` renders only when `model.errors.any?` — confirmed by triggering a validation error on exchange account create
- [ ] `DataTableComponent` renders thead with correct column labels; rows render via slots

### Smoke-Test Checklist (Manual, Pre-Merge PR 2)

- [ ] Dashboard load: all stat cards display values, P&L cards show green/red correctly
- [ ] Spot portfolio: tab switching works (portfolio ↔ transactions); date filter submits and updates table
- [ ] Trades index: column visibility toggle still works (Stimulus + UserPreference)
- [ ] Exchange account create: form submits, validation errors surface as `ErrorSummaryComponent`
- [ ] New transaction modal: opens via trigger button, form submits or cancels correctly, Stimulus `dialog` controller fires

### Quality Gates

- [ ] `bin/rails test` passes (green)
- [ ] `bundle exec rubocop` passes on new `app/components/` files
- [ ] No Tailwind classes from components are purged in a production build (`bin/rails assets:precompile`)

---

## Industry best practices (research)

Actionable recommendations from external docs and community for ViewComponent + Tailwind v4 + Hotwire (Turbo, Stimulus). Use these to validate and refine the migration.

### 1. Keeping Stimulus `data-*` attributes when moving markup into components

- **Problem:** Components that wrap buttons, forms, or containers must allow callers to pass Stimulus `data-controller`, `data-action`, `data-*-target`, etc., without the component having to know every controller name.
- **Recommendation:** Use **HTML attribute passthrough** on the root (or relevant) element. Two patterns:
  - **Rails 7 `tag.attributes`:** In the component, accept an options hash (e.g. `html_options` or `button_options`) and render it with `tag.attributes(**options)` in the template. Callers pass `data: { controller: "modal", action: "click->modal#open" }` (Rails converts to `data-controller`, `data-action`).  
    Example: `<button <%= tag.attributes(**button_options) %>>`
  - **view_component-contrib:** The [Evil Martians article](https://evilmartians.com/chronicles/viewcomponent-in-the-wild-embracing-tailwindcss-classes-and-html-attributes) uses `html_option :input_attrs` and a `#dots` helper to spread attributes; the same idea—don’t enumerate every `data-*` key, accept a hash and merge/spread onto the element.
- **Convention:** Name the passthrough clearly (e.g. `**html_options` on `ButtonComponent`) and document that it’s for `data-*`, `class`, `aria-*`, etc. Keep required props (e.g. `label`, `href` vs button) explicit; use the hash for “everything else.”
- **References:** [ViewComponent in the Wild III: TailwindCSS classes & HTML attributes](https://evilmartians.com/chronicles/viewcomponent-in-the-wild-embracing-tailwindcss-classes-and-html-attributes) (Evil Martians); Rails 7 [tag.attributes](https://api.rubyonrails.org/classes/ActionView/Helpers/TagHelper.html#method-i-tag).

### 2. Tailwind v4 content scanning for `app/components`

- **v4 behavior:** Tailwind v4 **auto-scans** the project (no `content` array in config). It skips `node_modules`, `.gitignore`d files, and binary/CSS. If `app/components/` is under the project root and not gitignored, it is usually scanned.
- **When to add `@source`:** If classes from component templates are missing from the built CSS (e.g. a class only used in `app/components/` doesn’t appear in `app/assets/builds/`), explicitly register the path in your main Tailwind CSS file:
  ```css
  @import "tailwindcss";
  @source "../../app/components";   /* path relative to the CSS file */
  ```
- **Optional: disable auto-detection** if you want strict control (e.g. multiple apps in a monorepo): `@import "tailwindcss" source(none);` then list every `@source "../app/components"`, `@source "../app/views"`, etc.
- **Action for this migration:** As in the plan, add a component that uses a unique class (e.g. `bg-teal-300`), run `bin/rails tailwindcss:build`, and confirm the class is in the output. If not, add `@source "../../app/components"` to `app/assets/tailwind/application.css`.
- **References:** [Detecting classes in source files](https://tailwindcss.com/docs/content-configuration) (Tailwind v4); [Restore Support for Custom content Paths (Discussion #18095)](https://github.com/tailwindlabs/tailwindcss/discussions/18095).

### 3. Form components: `data: { turbo: false }` and GET forms

- **`data: { turbo: false }`:** Use on `form_with` when you want a **full page submit** (no Turbo Drive). Rails generates `data-turbo="false"`. Good for forms that must do a classic POST/GET and full page reload (e.g. some filters or legacy flows). In a form component, pass options through to `form_with` (e.g. `form_options` or `**form_html`) so the caller or component can set `data: { turbo: false }`.
- **GET forms and Turbo Stream:** GET requests do **not** send `Accept: text/vnd.turbo-stream.html` by default. To get a Turbo Stream response from a GET form (e.g. filter that updates a frame), use `data: { turbo_stream: true }` on the form so the request asks for turbo-stream and the server can respond with `format.turbo_stream`. For a “plain” GET that just reloads the page, `data: { turbo: false }` is sufficient.
- **Recommendation for DateRangeFilterComponent:** If the form is GET and should update a turbo frame (e.g. table), add `data: { turbo_stream: true }` (or the equivalent that your Stimulus/controller expect). If it’s a full-page GET, use `data: { turbo: false }` so behavior is explicit. Keep the existing `data-controller="auto-submit-form"` via attribute passthrough (see §1).
- **References:** [Turbo Streams for GET forms (hotwired/turbo #463)](https://github.com/hotwired/turbo/issues/463); [Rails 7 can not set format turbo_stream with form method get](https://stackoverflow.com/questions/76280088/rails-7-can-not-set-format-turbo-stream-with-form-method-get).

### 4. Modal/dialog components with existing Stimulus controllers

- **Pattern:** Keep the Stimulus controller (e.g. `dialog`) unchanged. The ViewComponent only renders the HTML structure and attributes the controller expects (e.g. `data-controller="dialog"`, `data-dialog-target="backdrop"`, `data-action="...">`). Use attribute passthrough for the wrapper so the page can pass `data-controller` and any targets/actions if needed, or hardcode them in the component template if there’s a single canonical modal pattern.
- **Structure that works:** (1) Layout has a turbo frame (e.g. `turbo_frame_tag "modal"`) for modal content. (2) Modal component renders the overlay + panel; panel contains (or is) the turbo frame. (3) Stimulus controller opens/closes on `turbo:frame-load` and optionally on `turbo:submit-end` to close after a successful form submit. (4) Trigger links/buttons use `data-turbo-frame="modal"` and `href` to load content into the frame.
- **Recommendation:** Implement `ModalComponent` as in the plan: same DOM and `data-*` as the current partial so the existing `dialog` controller keeps working. No JS changes. If the modal is used in multiple contexts with different controllers, add an optional `html_options` (or `wrapper_options`) passthrough for the root element so callers can override or add `data-controller`.
- **References:** [Building a Turbo-Enabled Modal in Rails with View Components and Stimulus](https://eagerworks.com/blog/turbo-enabled-modal-rails); [How to create Modals with Rails and Hotwire (and Tailwind CSS)](https://railsdesigner.com/modal-with-rails-hotwire).

### 5. Class name merging (`class_names`, `tailwind_merge`) in components

- **Problem:** Tailwind utilities are order-independent; last class in the stylesheet wins. So “base + override” only works if conflicting classes are merged (e.g. `p-4` from component and `p-2` from caller → one padding wins). Rails’ `class_names` doesn’t resolve Tailwind conflicts.
- **Recommendation:** Use **tailwind_merge** (Ruby gem) on the final class string so that conflicting utilities are resolved (e.g. `merge("p-4 p-2")` → `"p-2"`). In `ApplicationComponent`, add a helper that combines `class_names` (for conditionals) with tailwind_merge:
  ```ruby
  def tailwind_class_names(*classes)
    TailwindMerge::Merger.new.merge(class_names(*classes))
  end
  ```
  Use it for the component’s root (and any variant/override) and accept an optional `class:` from the caller, then merge: `tailwind_class_names("base classes", @class_override, variant_classes)`.
- **Override API:** Expose a single override slot via a keyword arg: `def initialize(..., class: nil)` and store with `@class_override = binding.local_variable_get(:class)` so callers can do `render ButtonComponent.new(..., class: "rounded-lg text-xl")` and get correct override behavior.
- **Optional:** For many variants and compound variants (e.g. disabled + outline), consider [view_component-contrib](https://github.com/palkan/view_component-contrib) Style Variants with `style_config.postprocess_with { |classes| TailwindMerge::Merger.new.merge(classes.join(" ")) }` to keep templates clean.
- **References:** [Better ViewComponent + Tailwind (in Rails)](https://writing.tonydewan.com/posts/better-viewcomponent-tailwind-in-rails) (Tony Dewan); [ViewComponent in the Wild III](https://evilmartians.com/chronicles/viewcomponent-in-the-wild-embracing-tailwindcss-classes-and-html-attributes); [tailwind_merge gem](https://github.com/gjtorikian/tailwind_merge).

### 6. N+1 and performance when rendering many small components

- **N+1:** Not caused by ViewComponent itself. N+1 comes from data: avoid calling associations or scopes inside components (e.g. `@dashboard.summary_balance` is fine; `@portfolio.positions.count` inside a component can N+1 if not preloaded). Pass **scalars or preloaded collections** into components; keep controllers (or services) responsible for loading and eager-loading.
- **Render cost:** ViewComponent creates one object and one template render per instance. Benchmarks show components can be **faster** than partials in micro-benchmarks (e.g. ~2.5x in ViewComponent’s own benchmark), but some real-world pages with many components have been reported **slower** (e.g. 3x slower in one dashboard case) when there are many small components. Mitigations: (1) Reduce permutations—fewer variants and one-off components. (2) Prefer composition over deep inheritance. (3) For tables, avoid “one row = one component” at 100+ rows; use one component that loops over a collection and renders `<tr>` internally, or enforce pagination (e.g. 25 rows).
- **Profiling:** Enable `config.view_component.instrumentation_enabled = true` and subscribe to `render.view_component` (e.g. with rack-mini-profiler) to see time per component. Note: instrumentation adds overhead; use for profiling, not in production by default. Use Rails 7 Server-Timing in development to see `render.view_component` in browser DevTools.
- **Recommendation for this migration:** As in the plan’s performance section: pass scalars to StatCards; keep table row count bounded (pagination); don’t add caching in the first pass. If a page grows to 100+ component instances, consider collapsing table rows into one component that iterates.
- **References:** [ViewComponent Instrumentation](https://viewcomponent.org/guide/instrumentation.html); [View component is significantly slower than partials (Issue #345)](https://github.com/ViewComponent/view_component/issues/345); [Best practices (reduce permutations, composition)](https://viewcomponent.org/guide/best-practices.html) (if available); plan’s “Performance considerations” section above.

---

## Performance considerations

Concise, actionable notes from a performance review of the migration (server-side ERB + many small components).

### 1. N+1 and extra queries

- **StatCardComponent / dashboard:** Safe. Dashboard data comes from `Dashboards::SummaryService` as an `OpenStruct` of precomputed scalars. Views must pass those scalars (e.g. `value: @dashboard.summary_balance`) into `StatCardComponent` — do **not** pass AR or summary objects and call methods on them inside the component.
- **ErrorSummaryComponent:** Uses `model.errors.any?` and `model.errors.full_messages`. Errors are loaded when the model is validated; no extra query if the model is already in memory from the controller. Avoid re-validating or touching other associations inside the component.
- **DataTableComponent + rows:** N+1 risk is at the **call site**. The view will do something like `@positions.each { |pos| render RowComponent(...) }`. Controllers must already eager-load and paginate: trades index uses `pagy` (limit 25); spot/stocks use in-memory position arrays. **Recommendation:** In the migration, keep passing preloaded collections; add a one-line comment in the view or controller that the collection must be loaded/eager-loaded before rendering the table.
- **TabNavComponent (trades):** Trades index iterates `@exchange_accounts` to build tabs. Ensure `TradesController` loads `exchange_accounts` once (e.g. in a single query or as part of a shared load), not per-tab.

### 2. Render cost of many component instances

- **Typical counts:** Dashboard ~20+ StatCards + 3 Card wrappers; trades index up to 25 rows (paginated) + TabNav + DateRangeFilter + EmptyState; spot/stocks similar. Total on heavy pages is on the order of 30–50 component instances.
- ViewComponent allocates one Ruby object per render and does one template lookup/render per instance. For this count and simple templates (no heavy logic), expect sub-10 ms overhead over a single ERB file. If a page grows to 100+ rows, consider **not** using one `RowComponent` per row: use a single component that accepts a collection and loops internally (e.g. `DataTableComponent` with `rows: @positions` and an internal `each`), or enforce a hard cap (e.g. pagination already limits trades to 25).
- **Recommendation:** Proceed with the current design. Add a guideline: for tables, prefer the existing pagination (or a low row limit); if a future page needs 100+ rows, use a single loop inside one component or a partial instead of 100 slot-based row components.

### 3. Tailwind build size and purging

- Classes live in component templates under `app/components/`. Tailwind v4 (oxide) auto-scans the project; the plan already includes verifying that `app/components/` is scanned (e.g. unique class smoke test) and a quality gate: no component classes purged in production build.
- **No duplication concern:** The same utility strings move from 18 view files into ~10 component templates. Total set of class names is unchanged or smaller; CSS output size should be unchanged or slightly smaller.
- **Action:** In Phase 1, add the explicit `@source "../../app/components"` in `app/assets/tailwind/application.css` if the smoke test shows classes are missing, and keep the precompile check in the merge checklist.

### 4. Caching and fragment caching

- No fragment caching is used in the current views; the plan does not introduce it.
- **Opportunities if needed later:**
  - **TabNavComponent:** Cache key like `"tab_nav/#{controller_name}/#{@view}"` (or by path). TTL short or skip if tabs change rarely.
  - **DateRangeFilterComponent:** Low benefit (form is cheap).
  - **Dashboard cards / SummaryService:** If `SummaryService` becomes expensive, cache the **service result** (or the whole dashboard section) with a key including `current_user.id` and portfolio/date, rather than caching each StatCard.
- **Recommendation:** Do **not** add caching in the migration. Document the above as future options if profiling shows dashboard or tab rendering as hot spots.

### 5. Batching and limiting component usage

- **StatCards:** 6–8 per section is fine; no batching needed.
- **Table rows:** Keep the `renders_many :rows` slot API. Enforce pagination (already 25 for trades) and avoid rendering hundreds of row components on one page. If a new feature needs a very long table, prefer a single component that iterates over a collection and renders `<tr>` in one template.
- **Buttons/Badges:** Many per page is acceptable; no change.

**Summary:** The migration is performance-safe if (1) views pass scalars/preloaded data into components and do not trigger new queries, (2) Tailwind is confirmed to scan `app/components/` and the production build is checked, (3) table row count stays bounded by existing pagination or a small limit, and (4) caching is left for a later optimization pass if profiling justifies it.

---

## Dependencies & Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| `view_component` ~> 3.x slots API changes in minor release | Low | Pin to `~> 3.22` (avoid 3.21.0); review changelog before `bundle update` |
| Tailwind v4 purges component classes | Medium | Smoke test before migrating any views (Phase 1 step); add `@source "../../app/components"` if needed |
| `ApplicationHelper` include in component raises in test/preview context | Low | ApplicationHelper methods (`format_money`, `interval_hint`) have no controller dependency — verified safe. Document: new helpers that depend on request/controller/session should be checked in component context |
| `pl_color_class` nil scope (stat vs table cell) | Low | Use for stat/summary only (nil → slate-900). Table-cell nil → slate-500 remains out of scope or in phase 2 TradeCellComponent |
| `FormFieldComponent` doesn't cover select/date fields → partial migration | Known | Documented gap. Portfolio forms and exchange forms will have mixed inline + component field rendering until phase 2 |
| Big-bang view replacement introduces regression with no test coverage | Medium | Two-PR strategy; manual smoke-test checklist before merging PR 2. Optional: 1–2 ViewComponent tests in PR 1; one system test per cluster in PR 2 |
| Modal/date filter Stimulus behavior | Medium | Implement `open_on_connect` on Modal and `auto_submit_form_target: "trigger"` on date inputs (see Frontend subsection above) |

---

## Sources & References

### Origin

- **Brainstorm document:** [docs/brainstorms/2026-03-15-viewcomponent-migration-brainstorm.md](../brainstorms/2026-03-15-viewcomponent-migration-brainstorm.md)
  - Key decisions carried forward: primitive-first three-layer hierarchy; big bang scope; Tailwind utility classes inline in templates; Stimulus wiring preserved; tests as phase 2; no Storybook

### Internal References

- **Pattern analysis (deepen-plan):** [docs/plans/2026-03-15-001-viewcomponent-pattern-analysis.md](2026-03-15-001-viewcomponent-pattern-analysis.md) — naming, VARIANTS vs method, slots, render?, html_options.
- Button class strings: `app/helpers/application_helper.rb`, `app/views/exchange_accounts/new.html.erb`
- Stat card pattern: `app/views/dashboards/show.html.erb:12-30`
- Tab nav duplication: `app/views/spot/index.html.erb:4-7`, `app/views/stocks/index.html.erb:4-7`, `app/views/trades/index.html.erb`
- Modal pattern: `app/views/spot/index.html.erb`, `app/views/stocks/index.html.erb`
- Date filter pattern: `app/views/trades/index.html.erb:13-51`
- Existing Stimulus dialog controller: `app/javascript/controllers/dialog_controller.js`
- P&L ternary sites: `app/views/dashboards/show.html.erb:15,19,23`, `app/helpers/trades_helper.rb:85-89`
- Only existing partial: `app/views/portfolios/_form.html.erb`

### External References

- [ViewComponent gem](https://viewcomponent.org)
- [ViewComponent Slots API](https://viewcomponent.org/guide/slots.html)
- [ViewComponent + Tailwind CSS](https://viewcomponent.org/guide/tailwind_css.html)
