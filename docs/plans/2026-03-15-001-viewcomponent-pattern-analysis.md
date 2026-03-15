# ViewComponent Migration Plan — Pattern & Consistency Analysis

Analysis of the ViewComponent migration plan (Button, Badge, Card, StatCard, FormField, ErrorSummary, InlineFieldError, EmptyState, TabNav, DateRangeFilter, DataTable, Modal) for naming, variant handling, content/slot patterns, conditional render, and HTML passthrough.

---

## 1. Naming Consistency

### Component suffix ✅

All 12 components use the `Component` suffix and follow `ThingComponent` / `ThingThingComponent`:

- ButtonComponent, BadgeComponent, CardComponent  
- StatCardComponent, FormFieldComponent, ErrorSummaryComponent, InlineFieldErrorComponent  
- EmptyStateComponent, TabNavComponent, DateRangeFilterComponent, DataTableComponent, ModalComponent  

No inconsistency.

### Variant / style parameter naming ⚠️

| Component      | Parameter        | Values / role                          |
|----------------|------------------|----------------------------------------|
| Button         | `variant:`       | `:primary`, `:secondary`               |
| Badge          | `variant:`       | `:default`, `:success`, `:warning`, `:danger` |
| Card           | `padding:`       | `:default`, `:large` (not "variant")    |
| StatCard       | `size:`          | `:default` (plan does not use in template) |
| Modal          | `trigger_variant:` | `:primary` (delegates to Button)     |

**Findings:**

- **Semantic split:** "Variant" is used for visual style (Button, Badge). Card uses "padding", StatCard "size". That’s acceptable if the plan intends: variant = style, padding/size = layout/size. Naming could be aligned for style-only components (e.g. reserve `variant` for style and use `padding` / `size` only for layout/size).
- **StatCard `size:`:** Initializer accepts `size: :default` but the written template never uses `@size`. Either use it (e.g. different `value_css` or text size) or drop the argument to avoid dead API.
- **Recommendation:** Standardize on `variant:` for pure style (Button, Badge, Modal’s trigger). Keep `padding:` and `size:` for layout/size; document in the plan that "variant = style, other params = layout/size".

---

## 2. VARIANTS Hash vs Method Pattern

| Component   | Pattern                    | Where used                                  |
|------------|----------------------------|---------------------------------------------|
| Button     | `VARIANTS` hash             | In `initialize`: merge into `@html_options` |
| Badge      | `VARIANTS` hash             | In **template**: `BadgeComponent::VARIANTS[@variant]` |
| Card       | Inline / method-like       | In `initialize`: `padding == :large ? "p-8" : "p-6"` |
| StatCard   | Method                     | `value_css` (conditional string)            |
| TabNav     | Method                     | `tab_css(active)` (conditional string)      |

**Inconsistencies:**

1. **Button vs Badge:**  
   - Button resolves variant in the component class and stores the final class in `@html_options`.  
   - Badge stores `@variant` and the template reads `BadgeComponent::VARIANTS[@variant]`.  
   So: same "VARIANTS hash" idea, different place of use (init vs view). Prefer one rule: **resolve in the component, not in the template.** That keeps templates dumb and avoids the template depending on the constant.

2. **Hash vs method for style:**  
   - Button/Badge: hash lookup.  
   - Card: ternary in init.  
   - StatCard/TabNav: method returning a string.  
   For 2–4 options, both hash and method are fine. For Card, a small `PADDING_CLASSES = { default: "p-6", large: "p-8" }.freeze` (or a method) would align with Button/Badge and make adding options easier.

**Recommendations:**

- **Single rule:** "Variant/style classes are resolved in the Ruby component (initialize or private method), not in the template." Apply this to Badge: set e.g. `@variant_css = VARIANTS.fetch(@variant)` in `initialize` and use `@variant_css` in the template; remove template reference to `BadgeComponent::VARIANTS`.
- Prefer a **constant hash** for style maps (Button, Badge, and Card padding) and **methods** when logic is more than lookup (e.g. `value_css` depending on `@signed`, `tab_css(active)`). So: VARIANTS for fixed maps; methods when the string depends on state or extra args.

---

## 3. Slot vs Yield vs Passed Collection

| Component       | Mechanism              | Use case                          |
|----------------|-------------------------|-----------------------------------|
| Card           | `content` (yield)       | Single block, required             |
| EmptyState     | `content?` + `content`  | Optional block                     |
| Modal          | `content`               | Single block (body), required      |
| FormField      | —                       | No block                           |
| TabNav         | `tabs:` collection      | Data-driven list (label, url, active) |
| DataTable      | `renders_many :rows`    | Multiple row blocks                |

**Pattern logic:**

- **Default slot / `content`:** Used for one optional or required block (Card, EmptyState, Modal). Consistent.
- **Passed collection:** Used when items are data (TabNav: array of structs). No block needed; template iterates. Fits TabNav well.
- **Slot (`renders_many`):** Used when the caller supplies multiple blocks of the same kind (DataTable rows). Fits table rows.

**Recommendations:**

- Keep this split: **content** for single block, **collection** for data lists, **renders_many** for repeated block-based items. No change needed.
- In the plan, **DataTable** correctly uses an inner `RowComponent` and `renders_many :rows`; the slot lambda with `**attrs, &block` is appropriate. One small alignment: document in the plan that "use `content` for one block, pass arrays for data, use `renders_many` for multiple block-based items" so future components follow the same rule.

---

## 4. render? Usage (ErrorSummary, InlineFieldError) vs Always-Render

| Component              | Conditional render? | Condition                    |
|------------------------|----------------------|------------------------------|
| ErrorSummaryComponent  | Yes (`render?`)      | `@model.errors.any?`         |
| InlineFieldErrorComponent | Yes (`render?`)   | `@errors[@attribute].any?`   |
| All others             | No                   | Always render when used      |

**Findings:**

- Conditional render is limited to **error UI**: show something only when there are errors. That’s consistent and avoids empty error boxes.
- Other components don’t need `render?`: they are structural or always relevant when invoked (e.g. EmptyState is "there is no data", not "maybe no data").
- **Recommendation:** Keep as-is. Add a one-line convention in the plan: "Use `render?` only when the component’s entire output should be absent when a condition fails (e.g. error components). Otherwise, prefer always-render and let the caller decide whether to render the component."

---

## 5. html_options Passthrough (Button Only vs Others)

| Component | html_options / passthrough |
|-----------|----------------------------|
| Button    | `**html_options` merged with `class: VARIANTS.fetch(variant)`; supports `data-turbo-confirm`, `method:`, `form:`, etc. |
| Badge     | None                       |
| Card      | None                       |
| Others    | None                       |

**Findings:**

- Only **Button** accepts `**html_options`. That’s justified: buttons/links need `data-*`, `method`, `form`, etc. for Turbo and Rails. The plan documents this.
- **Merge order:** The plan uses `html_options.merge(class: VARIANTS.fetch(variant))`, so the **variant class wins** over any `class:` in `html_options`. If the intent is "caller can add attributes but not override variant", this is correct. If the intent is "caller can override class for one-off cases", you’d use `class: [VARIANTS.fetch(variant), html_options[:class]].compact.join(" ")` or similar. The plan’s current choice is consistent with "variant is authoritative."
- **Other components:** Card, Modal, EmptyState, etc. have no generic passthrough. That’s fine for the current scope. If later you need one-off wrapper attributes (e.g. extra class or `data-*` on Card/Modal), you can add optional `**html_options` (or a single `wrapper_class:`) without breaking the "Button is the main HTML-passthrough component" rule.

**Recommendations:**

- Keep Button as the only component with full `**html_options` for now; document that "only Button accepts arbitrary HTML attributes for link/button behavior."
- In the plan, explicitly state merge semantics: "Variant class takes precedence over a passed `class:` so that variant styling cannot be accidentally overridden."
- If you add wrapper options to other components later, prefer a narrow API (e.g. `wrapper_class:`) rather than full `**html_options` everywhere, to avoid unnecessary API surface.

---

## 6. Anti-Patterns to Avoid

1. **Template reaching into constants (Badge):** Template using `BadgeComponent::VARIANTS[@variant]` ties the view to the constant and duplicates "where style is resolved." Resolve in the component and pass a single class string (or method) to the template.

2. **Unused public API (StatCard `size:`):** Don’t expose `size: :default` if the template never uses it. Either use it (e.g. small/default/large text) or remove it before implementation.

3. **Mixing slot and collection for the same concept:** TabNav is data-only (collection); DataTable rows are block-based (slots). Don’t add a TabNav slot for "extra content per tab" and a parallel collection for tab data; keep one source of truth per concept.

4. **Overusing render?:** Use `render?` only when the component has no meaningful output (e.g. no errors). Don’t use it for "hide when empty" list components; keep EmptyState always-render and let the caller decide whether to show it.

5. **Adding html_options everywhere:** Keep passthrough on Button (and optionally on link-like components). Don’t add `**html_options` to every primitive "for consistency" without a real need; it complicates APIs and can blur component boundaries.

6. **RowComponent inheritance:** DataTable’s inner `RowComponent` is defined as `ViewComponent::Base` in the plan. For consistency and access to `pl_color_class` if ever needed, consider inheriting from `ApplicationComponent` or explicitly documenting that inner row components don’t need the base (and stay as `ViewComponent::Base`). Either is fine; just be explicit.

---

## 7. Summary: Pattern Alignments to Apply

| Area              | Current inconsistency / gap          | Suggested alignment |
|-------------------|--------------------------------------|---------------------|
| Variant resolution| Badge resolves in template           | Resolve in component; template uses `@variant_css` (or similar). |
| Style storage     | Card uses ternary in init            | Prefer constant hash (e.g. PADDING_CLASSES) or method; same pattern as Button/Badge. |
| StatCard          | `size:` not used in template         | Use it (e.g. in value_css) or remove from API. |
| Variant param name| variant vs padding vs size           | Document: `variant` = style; `padding`/`size` = layout/size; keep names as-is. |
| render?           | Only ErrorSummary, InlineFieldError  | Keep; add one-line convention for when to use `render?`. |
| html_options      | Button only                          | Keep; document merge semantics and that only Button gets passthrough. |
| Content/slots     | content vs collection vs rows        | Document: content = one block, collection = data list, renders_many = repeated blocks. |

Applying these will make the migration plan internally consistent and give a clear rule set for future components.
