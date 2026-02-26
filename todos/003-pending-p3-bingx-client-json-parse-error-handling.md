# P3: BingX client JSON parse and HTTP error handling

**Status:** complete  
**Priority:** p3  
**Tags:** code-review, quality, rails, resilience

## Problem Statement

In `BingxClient#signed_get`, the response body is parsed with `JSON.parse(res.body)`. If the server returns 200 with a non-JSON body (e.g. HTML error page, proxy timeout, or API gateway message), `JSON.parse` raises `JSON::ParserError`. That propagates as an unhandled exception and may not clearly indicate "invalid response body." Similarly, if `res.body` is nil, `res.body.presence && JSON.parse(res.body)` yields nil and the subsequent `res.code != "200"` branch uses `body&.dig(...)`, which is fine, but a 200 response with empty body would leave `body` nil and could cause confusing behavior.

## Findings

- **Location:** `app/services/exchanges/bingx_client.rb`, `signed_get` (around lines 109–114)
- `body = res.body.presence && JSON.parse(res.body)` — no rescue for `JSON::ParserError`.
- 200 with empty body: `body` would be nil; code then checks `res.code != "200"` and raises with `body&.dig('msg')` etc., so we'd raise "BingX API error 200: " which is acceptable but vague.

## Proposed Solutions

1. **Rescue JSON::ParserError:** Catch `JSON::ParserError` and raise a clear error such as "BingX API returned non-JSON response (status #{res.code}): #{res.body[0..200]}" so logs and jobs show the real cause.  
   - *Pros:* Better diagnostics.  
   - *Cons:* Slight extra code.  
   - *Effort:* Small.

2. **Leave as-is:** Rely on existing behavior; JSON parse errors are rare for a well-behaved API.  
   - *Pros:* No change.  
   - *Cons:* Harder to debug when proxy or BingX returns HTML.  
   - *Effort:* None.

## Recommended Action

Add a `rescue JSON::ParserError => e` and re-raise with a message that includes status code and a truncated body for debugging.

## Technical Details

- **Affected:** `Exchanges::BingxClient#signed_get`
- **Callers:** `fetch_my_trades`, `ping`, debug methods; all propagate exceptions to the job or console.

## Acceptance Criteria

- [ ] When BingX (or proxy) returns 200 with non-JSON body, the raised error message indicates "non-JSON" and includes status and a short body snippet (no secrets).
- [ ] Normal JSON responses unchanged.

## Work Log

- 2026-02-26: Code review – finding created.
- 2026-02-26: Rescue JSON::ParserError in signed_get; re-raise with message including status and truncated body snippet.
