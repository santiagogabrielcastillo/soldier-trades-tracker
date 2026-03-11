# P3: Document datetime/timezone behavior for New transaction

**Status:** complete  
**Priority:** p3  
**Tags:** code-review, ux, documentation

## Problem Statement

The "Date & time" field in the New transaction modal submits a value without timezone (e.g. `YYYY-MM-DDTHH:mm`). The app parses it with `Time.zone.parse` (application default time zone, often UTC) and stores `executed_at` in UTC. Users are not told whether the value is interpreted as local time or UTC, which can cause confusion.

## Findings

- **Location:** `app/controllers/spot_controller.rb` (`parse_executed_at`); `app/views/spot/index.html.erb` (datetime_local_field).
- **Plan:** The deepen-plan doc already noted: "For v1, document that input is interpreted in the app default time zone (or add user timezone later)."
- **Impact:** If the app time zone is UTC and the user is in another zone, entering "3:00 PM" may be stored as 3:00 PM UTC, not local.

## Proposed Solutions

1. **Add short hint in the UI**  
   Near the "Date & time" label or placeholder, add text such as "Stored in UTC" or "Enter time in your app time zone (see settings)."  
   **Pros:** Clear for users. **Cons:** Slight UI clutter. **Effort:** Small.

2. **Add to spot index or help**  
   One-time note or tooltip: "Transaction times are stored in UTC."  
   **Pros:** No form clutter. **Cons:** Less visible. **Effort:** Small.

3. **Defer and keep in plan only**  
   Rely on the plan doc; add user timezone preference later.  
   **Pros:** No change now. **Cons:** No in-app guidance. **Effort:** None.

**Recommended:** Option 1 or 2 so users understand how time is interpreted.

## Acceptance Criteria

- [x] Users can see (in UI or help) that transaction date/time is interpreted in a stated time zone (e.g. UTC or app default).
- [x] Optional: link or reference to where time zone is configured, if it exists.

## Work Log

- Added hint below the Date & time field in the New transaction modal: "Interpreted in <%= Time.zone.name %> and stored in UTC." so users know how the value is interpreted.
