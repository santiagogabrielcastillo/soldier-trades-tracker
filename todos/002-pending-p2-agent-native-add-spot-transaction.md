# P2: Agent-native parity — add spot transaction via API/tool

**Status:** complete  
**Priority:** p2  
**Tags:** code-review, agent-native, api

## Problem Statement

The "New transaction" flow exists only in the UI (modal form POST to `spot_transactions_path`). There is no API endpoint or agent tool to create a spot transaction. If the product aims for agent-native parity (any action a user can take, an agent can too), agents cannot add a spot transaction without driving the browser.

## Findings

- **Location:** Feature is UI-only; no `SpotTransactionsController` API or MCP/tool that creates a `SpotTransaction`.
- **Impact:** Agents can read spot data (if exposed elsewhere) but cannot create transactions programmatically.
- **Relevance:** Only applies if the project explicitly targets agent-native workflows; otherwise P3 or out of scope.

## Proposed Solutions

1. **Add a dedicated API endpoint (e.g. POST /api/spot/transactions)**  
   Authenticated endpoint that accepts token, side, amount, price_usd, executed_at and creates a `SpotTransaction` using the same logic as the controller (row_signature, normalization).  
   **Pros:** Clear contract; agents and other clients can use it. **Cons:** More surface to maintain and secure. **Effort:** Medium.

2. **Expose an agent tool (e.g. MCP or in-app tool)**  
   Tool that invokes the same create logic (service or controller action) so agents can "add_spot_transaction" with the same parameters.  
   **Pros:** Keeps UI as primary; tool is a thin wrapper. **Cons:** Depends on agent infrastructure. **Effort:** Medium.

3. **Defer**  
   If agent-native is not a goal, leave as-is and close as out of scope.  
   **Pros:** No work. **Cons:** No parity. **Effort:** None.

**Recommended:** Decide based on product roadmap; if agents should add transactions, implement 1 or 2.

## Acceptance Criteria

- [x] Product decision: agent-native parity for "add spot transaction" is required or not.
- [x] If required: an API or agent tool exists that creates a spot transaction with the same validation and row_signature behavior as the UI.
- [x] If not required: finding closed as out of scope.

## Work Log

- Implemented JSON API: same `create` action now responds to `format.json` with 201 + Location on success, 422 + error message on duplicate, and 422 + errors hash on validation failure. Agents can POST to `spot_transactions_path` with `Accept: application/json` and JSON body `{ "token", "side", "amount", "price_usd", "executed_at" }`. Test added for JSON create.
