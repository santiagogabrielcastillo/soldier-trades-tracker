# Deep Stock Analysis Feature — Claude API with Web Search

## Context

This is a Rails 8.1 investment tracker app (PostgreSQL, Solid Queue, Tailwind, ViewComponent, Stimulus, importmap-rails). It already has:

- **AI integration with Gemini** (`Ai::GeminiService`) — user provides their own API key, stored encrypted on the User model. Used for a chat assistant and for basic stock analysis.
- **Stock analysis pipeline**: `Stocks::AnalysisPromptBuilder` builds a prompt → `Ai::GeminiService` generates → `SyncStockAnalysisJob` orchestrates per-ticker → results upserted into `stock_analyses` table (rating, executive_summary, risk_reward_rating, thesis_breakdown, red_flags).
- **Fundamentals from Finviz**: `StockFundamental` model with P/E, forward P/E, PEG, P/S, P/FCF, EV/EBITDA, margins, ROE, ROIC, Debt/Equity, sales growth. Scraped via `SyncFundamentalsJob`.
- **Error hierarchy**: `Ai::Error < StandardError`, `Ai::RateLimitError`, `Ai::InvalidKeyError`, `Ai::ServiceError`.
- **Provider pattern for exchanges**: `Exchanges::ProviderForAccount` registry — same pattern we want for AI providers.

The goal is to add a **deep analysis feature** powered by Claude's API with the web search tool. Claude autonomously searches for current data (prices, earnings, analyst sentiment, investigations, CEO changes) and produces a rich structured analysis following an owner-mentality value investment framework.

## What we're building

### 1. `Ai::ClaudeService` (new)

A service that mirrors `Ai::GeminiService` interface but hits the Anthropic Messages API with web search enabled.

**Key API details:**
- Endpoint: `https://api.anthropic.com/v1/messages`
- Auth: `x-api-key` header (not query param like Gemini)
- Required headers: `anthropic-version: 2023-06-01`, `content-type: application/json`
- Model: `claude-sonnet-4-6` (best cost/quality for this use case)
- Web search tool: `{ type: "web_search_20260209", name: "web_search", max_uses: 10 }`
- Response shape: `data["content"]` is an array of blocks (`type: "text"` for text, `type: "tool_use"` for tool calls). Extract all text blocks and join them.
- Timeout: needs to be longer than Gemini — 120 seconds read_timeout (web search + reasoning takes 30-90s per ticker)
- Must raise the same `Ai::Error` family (RateLimitError on 429, InvalidKeyError on 401/403, ServiceError on others)

**Interface must match GeminiService:**
```ruby
client = Ai::ClaudeService.new(api_key: "sk-ant-...")
result = client.generate(prompt: "Analyze AAPL")
# → returns string (the text content)
```

But also support a richer call with tools:
```ruby
result = client.generate(prompt: "...", tools: [...], system: "...")
```

### 2. `Ai::ProviderForUser` (new)

Registry that picks the right AI service based on user's tier/configuration.

```ruby
Ai::ProviderForUser.new(user).client
# → Ai::GeminiService (free tier, user's own key)
# → Ai::ClaudeService (paid tier, platform key from credentials)
```

**Design decisions to make:**
- For now, simplest path: users on Claude tier use a platform-level API key stored in Rails credentials (`Rails.application.credentials.dig(:anthropic, :api_key)`). No user-provided Claude key yet.
- Need a `tier` or `ai_provider` field on User model (or infer from presence of keys).
- Gemini users get the existing simple analysis (fundamentals only, no web search).
- Claude users get the deep analysis (web search enabled, richer output).

### 3. `Stocks::DeepAnalysisPromptBuilder` (new)

Replaces `AnalysisPromptBuilder` for Claude-tier users. Embeds:
- The full owner-mentality investment framework (moat scoring, solvency checks, value trap classification, turnaround detection)
- Available fundamentals from `StockFundamental` (same data the current builder injects)
- Instructions to use web search for: current price, recent earnings, analyst sentiment, crisis/turnaround events, management guidance
- A structured JSON output schema for the rich visual display

**The framework content lives in these files (attached to the project):**
- `equity-analyst/SKILL.md` — main analysis framework (Phase 2 logic)
- `equity-analyst/references/report-template.md` — output structure
- `equity-analyst/references/sector-notes.md` — sector-specific adjustments

The prompt should instruct Claude to:
1. Search the web for current data on the ticker (price, recent earnings, news, analyst ratings)
2. Combine web findings with the fundamentals we provide
3. Apply the investment framework
4. Return ONLY a JSON object matching our schema (below)

### 4. Structured JSON output schema

The prompt must request this exact structure so the frontend can render it:

```json
{
  "verdict": "buy|accumulate|watch|hold|sell",
  "verdict_label": "Buy — strong fundamentals at cyclical low",
  "company_name": "ServiceNow",
  "analyzed_at": "2026-04-14",

  "metrics": {
    "price": { "value": "$89", "subtitle": "-58% from 52w high" },
    "market_cap": { "value": "$93B", "subtitle": "1.04B shares" },
    "forward_pe": { "value": "~20x", "subtitle": "vs 5y avg ~188x" },
    "ev_revenue": { "value": "~5.6x", "subtitle": "vs 10y median 15.3x" },
    "net_debt_ebitda": { "value": "Net cash", "subtitle": "$6.3B cash vs $2.4B debt", "status": "excellent|acceptable|warning|red_flag" },
    "fcf_margin": { "value": "35%", "subtitle": "$4.58B FCF" },
    "renewal_or_retention": { "value": "98%", "subtitle": "Multi-year streak" },
    "revenue_growth": { "value": "21%", "subtitle": "FY25 YoY" }
  },

  "moat": {
    "overall": "wide|narrow|none",
    "scores": {
      "switching_costs": { "score": 5, "max": 5 },
      "scale_advantage": { "score": 4, "max": 5 },
      "network_effect": { "score": 2, "max": 5 },
      "intangibles": { "score": 4, "max": 5 }
    },
    "primary_threat": "AI agents reducing per-seat license demand"
  },

  "revenue_trend": [
    { "year": "FY21", "revenue": 5.9, "fcf": 1.9 },
    { "year": "FY22", "revenue": 7.3, "fcf": 2.2 },
    { "year": "FY23", "revenue": 9.0, "fcf": 2.7 },
    { "year": "FY24", "revenue": 11.0, "fcf": 3.4 },
    { "year": "FY25", "revenue": 13.3, "fcf": 4.6 }
  ],
  "revenue_unit": "B",

  "tags": [
    { "label": "Asset light", "color": "green" },
    { "label": "Net cash position", "color": "green" },
    { "label": "98% renewal", "color": "green" },
    { "label": "AI disruption risk", "color": "amber" },
    { "label": "SBC ~18% of rev", "color": "red" }
  ],

  "asset_classification": "light|heavy|hybrid",
  "turnaround_mode": false,
  "turnaround_bucket": null,

  "executive_summary": "3-5 sentence analysis...",
  "thesis_breakdown": "Detailed qualitative + quantitative analysis...",
  "risk_reward_rating": "Excellent|Good|Fair|Poor — one sentence...",
  "red_flags": "Numbered red flags...",
  "what_to_watch": "Upcoming catalysts and events...",
  "sources": ["url1", "url2"]
}
```

### 5. Database migration

Add `structured_data` JSONB column to `stock_analyses`:

```ruby
add_column :stock_analyses, :structured_data, :jsonb
add_column :stock_analyses, :provider, :string, default: "gemini"
```

The existing text columns (executive_summary, thesis_breakdown, etc.) stay for backward compat with Gemini results. Claude results populate BOTH the text columns (for backward compat) AND `structured_data` (for the rich UI).

### 6. `SyncStockAnalysisJob` update

Modify to use `Ai::ProviderForUser` instead of hardcoded Gemini. When provider is Claude:
- Use `DeepAnalysisPromptBuilder` instead of `AnalysisPromptBuilder`
- Increase `RATE_LIMIT_DELAY` to ~3.0 seconds (Claude web search takes longer)
- Parse the structured JSON response and store in `structured_data`
- Also extract the text fields for backward compat columns
- Increase timeout handling (Claude + web search can take 60-90 seconds)

### 7. Frontend: `StockAnalysisCardComponent` (new ViewComponent)

Renders the rich visual analysis from `structured_data`. Follows existing app patterns (Tailwind, ViewComponent).

**Sections (top to bottom):**
1. **Verdict badge** — colored pill (green=buy/accumulate, amber=watch/hold, red=sell)
2. **Metric cards** — 2x4 grid of StatCardComponent-style cards showing price, market cap, P/E, EV/rev, debt/EBITDA, FCF margin, retention, growth
3. **Moat scorecard** — horizontal bars or dots (5-dot scale) for each moat dimension
4. **Revenue vs FCF trend** — simple horizontal bar chart (CSS only, no Chart.js needed) or use Chart.js if you prefer
5. **Key tags** — colored pills (green/amber/red) summarizing strengths and risks
6. **Prose sections** — expandable/collapsible sections for executive summary, thesis, red flags, what to watch

**Where it renders:**
- Option A: New detail page (`GET /stocks/analysis/:ticker`) linked from the AI Rating badge in the fundamentals table
- Option B: Modal/drawer triggered by clicking the rating badge
- I'd suggest Option A — it's simpler and gives room for the full analysis

### 8. Settings page update

Add Claude/Anthropic configuration option alongside existing Gemini setup. For MVP, this could be as simple as a toggle or a second API key field. The tier-gating logic can come later.

## Build order (suggested)

1. **Migration** — add `structured_data` JSONB and `provider` string to `stock_analyses`
2. **`Ai::ClaudeService`** — new service, test with a simple prompt first
3. **`Ai::ProviderForUser`** — registry, route by user config
4. **`Stocks::DeepAnalysisPromptBuilder`** — the big prompt with framework + JSON schema
5. **Update `SyncStockAnalysisJob`** — use provider registry, handle both prompt builders
6. **`StockAnalysisCardComponent`** — the rich visual output
7. **Detail page/route** — wire up the component to a view
8. **Settings update** — let users configure Claude access
9. **Tests** — service tests, job tests, component tests

## Key files to study before starting

- `app/services/ai/gemini_service.rb` — pattern to follow for ClaudeService
- `app/services/ai/errors.rb` — error hierarchy to reuse
- `app/services/stocks/analysis_prompt_builder.rb` — current prompt, understand what exists
- `app/jobs/stocks/sync_stock_analysis_job.rb` — orchestration job to modify
- `app/views/stocks/_fundamentals_table.html.erb` — where ratings display today
- `db/schema.rb` — current stock_analyses schema
- `app/services/exchanges/provider_for_account.rb` — registry pattern to follow for AI providers
- `app/controllers/ai_controller.rb` — existing AI integration surface
- `app/views/settings/show.html.erb` — where API key config lives

## Important constraints

- **No new gems** if possible. `net/http` + `json` (already used by GeminiService) is sufficient for the Claude API.
- **Solid Queue** for background jobs (already configured).
- **Tailwind + ViewComponent** for frontend (match existing patterns).
- **importmap-rails** for JS — no webpack/esbuild.
- **Keep Gemini working.** This is additive — existing free-tier Gemini flow must not break.
- **Cost awareness:** Claude Sonnet 4.6 = $3/$15 per MTok. Web search = $10/1000 searches. Budget ~$0.15-0.30 per ticker analysis. Consider a daily cap per user.

## Attached reference files

The investment framework that powers the prompt lives in these three files. They were developed iteratively by analyzing ServiceNow (NOW) and UnitedHealth (UNH) as test cases:

- `equity-analyst/SKILL.md` — The main analysis framework. Phase 2 (analysis logic) and the edge-case handling go into DeepAnalysisPromptBuilder. Phase 1 (research) is handled by Claude's web search tool autonomously.
- `equity-analyst/references/report-template.md` — Output structure (adapt to JSON schema above instead of markdown).
- `equity-analyst/references/sector-notes.md` — Sector-specific adjustments for financials, insurance, energy, REITs, healthcare, tech. Include conditionally in the prompt based on `StockFundamental#sector`.
