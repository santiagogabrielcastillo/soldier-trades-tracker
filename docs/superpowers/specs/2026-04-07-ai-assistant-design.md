# AI Assistant Feature — Design Spec

**Date:** 2026-04-07  
**Status:** Approved

## Overview

Add a BYOK (Bring Your Own Key) AI assistant powered by Google Gemini to the portfolio tracker. Each user stores their own Gemini API key (encrypted at rest). The assistant can analyze crypto futures trading performance, spot holdings, stock portfolios, watchlist valuations, and asset allocation. The UI is a floating slide-in panel accessible from every page.

## Tech Stack Constraints

- **Rails 7.2**, importmap-rails (no Node/npm build step)
- **No new gems** — Gemini API called via `Net::HTTP` (same pattern as Binance/BingX clients)
- **Rails 7.2 encryption** (`encrypts :gemini_api_key`) for key storage
- **Stimulus + Turbo** for all frontend behavior
- Architecture: Option A — controller + JSON endpoint + Stimulus (no streaming, no background jobs)

## 1. Data Model

### Migration

Add nullable encrypted column to `users` table:

```
gemini_api_key :text (encrypted via Rails 7.2 encrypts)
```

### User model changes

```ruby
encrypts :gemini_api_key

def gemini_api_key_configured?
  gemini_api_key.present?
end

def gemini_api_key_masked
  return nil unless gemini_api_key.present? && gemini_api_key.length >= 8
  "#{gemini_api_key[0..3]}...#{gemini_api_key[-4..]}"
end
```

No new table. No associations. The key is stored on the existing `users` record.

## 2. Service Layer

### `app/services/ai/gemini_service.rb`

Initialized with `api_key:`. One public method: `generate(prompt:)`.

- POSTs to `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key={api_key}`
- Request body: `{ contents: [{ parts: [{ text: prompt }] }] }`
- Uses `Net::HTTP` with SSL, 10s open timeout, 30s read timeout
- Parses response: `candidates[0].content.parts[0].text`
- Raises:
  - `Ai::RateLimitError` on HTTP 429
  - `Ai::InvalidKeyError` on HTTP 400, 401, 403
  - `Ai::ServiceError` on other non-200 responses or parse failures

### `app/services/ai/portfolio_context_builder.rb`

Initialized with `user:`. One public method: `call` → returns a markdown string.

Sections included:

1. **Crypto Futures** — all open positions + up to 50 most recent closed positions for the user (capped to keep token count reasonable). Columns: symbol, side, entry price, current price (if open), P&L, ROI%, leverage, status.
2. **Spot Holdings** — from `Spot::PositionStateService`. Columns: token, balance, avg cost, current price, unrealized P&L.
3. **Stock Portfolio** — from `Stocks::PositionStateService`. Columns: ticker, shares, avg cost, current price, unrealized P&L.
4. **Asset Allocation** — via `Allocations::SummaryService` (reuses existing service). Columns: bucket name, target %, actual %, drift %.
5. **Watchlist** — from `WatchlistTicker` + `StockFundamental` (joined). Columns: ticker, P/E, EPS, market cap (when available); ticker only when no fundamentals.

Each section is formatted as a Markdown table with a header line. Missing or empty sections are noted with "No data available."

### System prompt

```
You are a portfolio analysis assistant for a complete investment tracker.
You have access to the user's crypto futures trading positions, spot holdings,
stock portfolio, asset allocation, and watchlist with fundamentals.
Provide insights about trading performance, diversification, sector/asset exposure,
risk, and watchlist valuations when asked.
You are NOT a financial advisor — always remind users to do their own research.
Never give specific buy/sell recommendations.
Be concise and data-driven in your analysis.
Today's date: {date}.
```

The final prompt sent to Gemini is: `{system_prompt}\n\n{portfolio_context}\n\nUser question: {message}`

### Error classes

```
app/services/ai/errors.rb
  Ai::Error < StandardError
  Ai::RateLimitError < Ai::Error
  Ai::InvalidKeyError < Ai::Error
  Ai::ServiceError < Ai::Error
```

## 3. Controllers & Routes

### `app/controllers/ai_controller.rb`

Both actions require authentication (via `ApplicationController` before_action).

#### `POST /ai/chat`

- Params: `{ message: string }`
- If `current_user.gemini_api_key` is blank → `render json: { error: "no_api_key", message: "Please add your Gemini API key in Settings." }, status: :unprocessable_entity`
- Builds context via `Ai::PortfolioContextBuilder.new(user: current_user).call`
- Calls `Ai::GeminiService.new(api_key: current_user.gemini_api_key).generate(prompt:)`
- Success: `render json: { response: text }`
- `Ai::RateLimitError` → `{ error: "rate_limited", message: "You've hit your free tier limit. Try again in a moment." }`, status 429
- `Ai::InvalidKeyError` → `{ error: "invalid_key", message: "Your API key appears to be invalid. Please check it in Settings." }`, status 401
- `Ai::ServiceError` → `{ error: "service_error", message: "The AI service is temporarily unavailable." }`, status 422

#### `POST /ai/test_key`

- Params: `{ api_key: string }`
- Calls `Ai::GeminiService.new(api_key: params[:api_key]).generate(prompt: "Say OK")` 
- Success: `render json: { ok: true }`
- Errors: same error shape as chat, appropriate status

### `app/controllers/settings_controller.rb` additions

- `PATCH /settings/ai_key` — saves `gemini_api_key` via `current_user.update(gemini_api_key: params[:api_key])`, redirects with flash
- `DELETE /settings/ai_key` — sets `current_user.update(gemini_api_key: nil)`, redirects with flash

### Routes additions

```ruby
resource :settings, only: %i[show update] do
  member do
    patch :ai_key
    delete :ai_key
  end
end
post "ai/chat", to: "ai#chat"
post "ai/test_key", to: "ai#test_key"
```

## 4. Frontend

### Stimulus controller: `app/javascript/controllers/ai_chat_controller.js`

Targets:
- `panel` — the slide-in drawer
- `trigger` — the floating FAB button
- `messageList` — scrollable chat history container
- `input` — textarea
- `sendBtn` — submit button
- `noKeyState` — shown when no API key configured
- `chatState` — shown when API key configured

Values:
- `hasKeyValue` (boolean) — set server-side in the HTML
- `chatUrlValue` (string) — `/ai/chat`

Actions:
- `toggle()` — open/close panel
- `send()` — POST to `/ai/chat`, append user message + AI response to messageList, handle errors inline
- `quickAction(event)` — sets input value from `data-prompt` attribute, calls `send()`
- `close()` — close panel on Escape key or overlay click

Cooldown: after each send, disable `sendBtn` for 3 seconds.

Markdown: AI responses rendered as plain text (no markdown library needed for MVP — Gemini responses are typically clean prose).

### Quick-action buttons

**Portfolio-wide:**
- "Analyze my full portfolio"
- "How diversified am I across asset classes?"
- "Summarize my overall asset allocation"

**Crypto Futures:**
- "Review my futures trading performance"
- "Where am I losing the most in futures?"
- "What's my win rate trend?"

**Spot:**
- "Analyze my spot crypto holdings"

**Stocks & Watchlist:**
- "Review my stock portfolio performance"
- "Evaluate my watchlist valuations"

### Floating trigger button

Fixed, bottom-right, `z-50`, indigo background, sparkle (✦) or wand icon. Always rendered in `application.html.erb` inside the authenticated layout (below the `<main>` tag). Hidden on mobile when panel is open (panel takes full width).

### Panel layout

- Fixed right side, full height, `w-96` on desktop / full-width on mobile
- Header: "AI Assistant" + close button
- No-key state: indigo info box with link to Settings
- Chat state: scrollable message list + quick-action grid + input row
- Footer note: "Powered by Gemini 2.5 Flash · Your key, your data"

### Settings page additions

New `<fieldset>` in `app/views/settings/show.html.erb`:

**When no key configured:**
```
[ text input for API key ] [ Test Connection ] [ Save ]
Note: Get your free key at Google AI Studio
```

**When key configured:**
```
Key: AIza...xxxx   [ Remove ]
[ Test Connection ]
```

Test Connection uses a fetch call to `POST /ai/test_key` with the current input value. Shows inline green "✓ Connected" or red error message.

## 5. Error States (UI)

| Error | UI Treatment |
|-------|-------------|
| No API key | Replace chat UI with indigo info box + link to Settings |
| Invalid key | Inline red message in chat: "Your API key is invalid. [Update in Settings]" |
| Rate limited | Inline amber message: "Free tier limit reached. Try again in a moment." |
| Service error | Inline red message: "AI service unavailable. Please try again." |

## 6. Security

- `gemini_api_key` encrypted at rest via Rails 7.2 `encrypts` — same as exchange account keys
- Raw key never returned in API responses after save — only masked version
- `ai/test_key` accepts the key in the request body (POST, not GET) — not logged in URL
- Key scoped to authenticated user — no cross-user access possible
- Context builder never includes other users' data

## 7. What's Excluded (YAGNI)

- Conversation history / multi-turn chat (stateless per request)
- Streaming responses
- Model selection UI (hardcoded to `gemini-2.5-flash`)
- Per-user rate limit tracking in DB (Gemini enforces this on their side)
- Export/share of AI responses
