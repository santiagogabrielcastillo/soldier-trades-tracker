# P2: Use strong parameters in SpotController#create

**Status:** complete  
**Priority:** p2  
**Tags:** code-review, rails, security

## Problem Statement

`SpotController#create` reads request parameters directly (`params[:token]`, `params[:side]`, etc.) instead of using Rails strong parameters. This bypasses the standard permit list and weakens defense-in-depth against mass assignment, even though the controller only assigns known attributes when building the record.

## Findings

- **Location:** `app/controllers/spot_controller.rb` (create action, lines 44–49, 95–108).
- **Current behavior:** Params are read ad hoc; token/side are normalized and validated in controller logic; no `params.require(:spot_transaction).permit(...)`.
- **Risk:** Low today (only known attrs are set), but any future assignment from params could introduce mass-assignment; strong params make the allowed set explicit and auditable.

## Proposed Solutions

1. **Add strong params and use them in create**  
   Define `spot_transaction_params` that permit `:token, :side, :amount, :price_usd, :executed_at`. In `create`, read from `spot_transaction_params` and normalize token/side/executed_at/decimals as now.  
   **Pros:** Aligns with Rails conventions; explicit allowlist. **Cons:** Slight refactor. **Effort:** Small.

2. **Leave as-is and add a comment**  
   Document that we intentionally build the record from a fixed set of keys and do not use mass assignment.  
   **Pros:** No code change. **Cons:** Still non-standard; future contributors might add params. **Effort:** Tiny.

**Recommended:** Option 1.

## Acceptance Criteria

- [x] `SpotController` has a private `spot_transaction_params` (or similar) that returns a permitted hash for the create form.
- [x] `create` uses that method (or its keys) for building the `SpotTransaction`; no direct `params[:key]` for create inputs.
- [x] Tests still pass.

## Work Log

- Implemented `spot_transaction_params` permitting `:token, :side, :amount, :price_usd, :executed_at`. `create` and `build_invalid_spot_transaction` now use the permitted hash.
