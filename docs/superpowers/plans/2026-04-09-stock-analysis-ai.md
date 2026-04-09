# Stock AI Analysis Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add per-user AI investment analysis for each stock ticker using the user's Gemini key, storing results in `stock_analyses` and displaying rating badges in the Valuations and Watchlist tabs.

**Architecture:** A new `StockAnalysis` model (user_id + ticker, unique) stores the parsed Gemini response. `Stocks::AnalysisPromptBuilder` constructs the thesis prompt from a ticker's `StockFundamental` record. `Stocks::SyncStockAnalysisJob` iterates over a user's open portfolio + watchlist tickers, calls `Ai::GeminiService`, parses JSON from the response, and upserts results. A new `sync_analysis` controller action enqueues the job. The `_fundamentals_table` partial receives an `analyses:` hash and renders rating badges.

**Tech Stack:** Rails 7.2, PostgreSQL, `Ai::GeminiService` (existing, Net::HTTP + JSON), minitest, Tailwind CSS.

---

## File Map

| File | Action | Purpose |
|---|---|---|
| `db/migrate/TIMESTAMP_create_stock_analyses.rb` | Create | `stock_analyses` table |
| `app/models/stock_analysis.rb` | Create | Model + `for_user_and_tickers` scope |
| `app/services/stocks/analysis_prompt_builder.rb` | Create | Build Gemini prompt from fundamentals |
| `app/jobs/stocks/sync_stock_analysis_job.rb` | Create | Per-user Gemini analysis job |
| `app/controllers/stocks_controller.rb` | Modify | `sync_analysis` action + load analyses in valuations/watchlist |
| `config/routes.rb` | Modify | Add `post "stocks/sync_analysis"` |
| `app/views/stocks/_fundamentals_table.html.erb` | Modify | Add `analyses:` + `analyze_url:` locals, rating badge cell |
| `test/models/stock_analysis_test.rb` | Create | Model scope tests |
| `test/services/stocks/analysis_prompt_builder_test.rb` | Create | Prompt content tests |
| `test/jobs/stocks/sync_stock_analysis_job_test.rb` | Create | Job behavior tests |
| `test/fixtures/stock_analyses.yml` | Create | Fixture data |

---

### Task 1: Migration and StockAnalysis model

**Files:**
- Create: `db/migrate/TIMESTAMP_create_stock_analyses.rb`
- Create: `app/models/stock_analysis.rb`
- Create: `test/models/stock_analysis_test.rb`
- Create: `test/fixtures/stock_analyses.yml`

- [ ] **Step 1: Generate migration**

```bash
cd /path/to/worktree && bin/rails generate migration CreateStockAnalyses \
  user:references ticker:string rating:string executive_summary:text \
  risk_reward_rating:string thesis_breakdown:text red_flags:text analyzed_at:datetime
```

- [ ] **Step 2: Edit the generated migration**

Open the generated file and ensure it reads exactly:

```ruby
class CreateStockAnalyses < ActiveRecord::Migration[7.2]
  def change
    create_table :stock_analyses do |t|
      t.references :user, null: false, foreign_key: true
      t.string   :ticker,             null: false
      t.string   :rating,             null: false
      t.text     :executive_summary
      t.string   :risk_reward_rating
      t.text     :thesis_breakdown
      t.text     :red_flags
      t.datetime :analyzed_at,        null: false

      t.timestamps
    end

    add_index :stock_analyses, [:user_id, :ticker], unique: true
  end
end
```

- [ ] **Step 3: Run migration**

```bash
bin/rails db:migrate
```

Expected: `== CreateStockAnalyses: migrating` then `migrated`.

- [ ] **Step 4: Create fixture** at `test/fixtures/stock_analyses.yml`:

```yaml
aapl_analysis:
  user: one
  ticker: AAPL
  rating: buy
  executive_summary: Strong moat with durable cash flows.
  risk_reward_rating: Good — low leverage, dominant brand.
  thesis_breakdown: Apple's ecosystem creates high switching costs. Asset-light services business growing. P/E premium justified.
  red_flags: None
  analyzed_at: 2026-04-09 10:00:00

msft_analysis:
  user: one
  ticker: MSFT
  rating: hold
  executive_summary: Fair value, strong but priced in.
  risk_reward_rating: Fair — reasonable leverage, cloud competition increasing.
  thesis_breakdown: Azure growth decelerating. Wide moat in enterprise software. PEG above 2 limits upside.
  red_flags: Valuation premium, slowing cloud growth
  analyzed_at: 2026-04-09 10:00:00
```

- [ ] **Step 5: Write failing model tests** at `test/models/stock_analysis_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class StockAnalysisTest < ActiveSupport::TestCase
  test "for_user_and_tickers returns hash indexed by ticker" do
    user = users(:one)
    result = StockAnalysis.for_user_and_tickers(user, ["AAPL", "MSFT"])

    assert_equal "buy",  result["AAPL"].rating
    assert_equal "hold", result["MSFT"].rating
  end

  test "for_user_and_tickers returns empty hash when no records" do
    user = users(:one)
    result = StockAnalysis.for_user_and_tickers(user, ["UNKNOWN"])

    assert_equal({}, result)
  end

  test "for_user_and_tickers ignores other users analyses" do
    user = users(:two)
    result = StockAnalysis.for_user_and_tickers(user, ["AAPL"])

    assert_empty result
  end

  test "validates presence of ticker, rating, analyzed_at" do
    analysis = StockAnalysis.new(user: users(:one))
    analysis.valid?

    assert_includes analysis.errors[:ticker], "can't be blank"
    assert_includes analysis.errors[:rating],  "can't be blank"
    assert_includes analysis.errors[:analyzed_at], "can't be blank"
  end
end
```

- [ ] **Step 6: Run tests to confirm they fail**

```bash
bin/rails test test/models/stock_analysis_test.rb
```

Expected: Failures — `StockAnalysis` doesn't exist yet.

- [ ] **Step 7: Create the model** at `app/models/stock_analysis.rb`:

```ruby
# frozen_string_literal: true

class StockAnalysis < ApplicationRecord
  belongs_to :user

  validates :ticker,      presence: true
  validates :rating,      presence: true
  validates :analyzed_at, presence: true

  def self.for_user_and_tickers(user, tickers)
    where(user: user, ticker: tickers).index_by(&:ticker)
  end
end
```

- [ ] **Step 8: Run tests to confirm they pass**

```bash
bin/rails test test/models/stock_analysis_test.rb
```

Expected: 4 tests, 0 failures.

- [ ] **Step 9: Commit**

```bash
git add db/migrate db/schema.rb db/queue_schema.rb \
        app/models/stock_analysis.rb \
        test/models/stock_analysis_test.rb \
        test/fixtures/stock_analyses.yml
git commit -m "feat(stocks): add StockAnalysis model and migration"
```

---

### Task 2: AnalysisPromptBuilder service

**Files:**
- Create: `app/services/stocks/analysis_prompt_builder.rb`
- Create: `test/services/stocks/analysis_prompt_builder_test.rb`

- [ ] **Step 1: Write failing tests** at `test/services/stocks/analysis_prompt_builder_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

module Stocks
  class AnalysisPromptBuilderTest < ActiveSupport::TestCase
    def build_fundamental(overrides = {})
      StockFundamental.new(
        ticker:     overrides.fetch(:ticker,     "AAPL"),
        pe:         overrides.fetch(:pe,         BigDecimal("28.5")),
        fwd_pe:     overrides.fetch(:fwd_pe,     BigDecimal("25.1")),
        peg:        overrides.fetch(:peg,        BigDecimal("2.3")),
        ps:         overrides.fetch(:ps,         BigDecimal("7.5")),
        pfcf:       overrides.fetch(:pfcf,       BigDecimal("30.2")),
        ev_ebitda:  overrides.fetch(:ev_ebitda,  BigDecimal("22.1")),
        net_margin: overrides.fetch(:net_margin, BigDecimal("25.31")),
        roe:        overrides.fetch(:roe,        BigDecimal("147.25")),
        roic:       overrides.fetch(:roic,       BigDecimal("55.1")),
        debt_eq:    overrides.fetch(:debt_eq,    BigDecimal("1.87")),
        sales_5y:   overrides.fetch(:sales_5y,   BigDecimal("2.02")),
        sales_qq:   overrides.fetch(:sales_qq,   BigDecimal("4.87")),
        sector:     overrides.fetch(:sector,     "Technology"),
        industry:   overrides.fetch(:industry,   "Consumer Electronics"),
        fetched_at: Time.current
      )
    end

    test "prompt includes ticker symbol" do
      fundamental = build_fundamental(ticker: "AAPL")
      prompt = Stocks::AnalysisPromptBuilder.call(ticker: "AAPL", fundamental: fundamental)

      assert_includes prompt, "AAPL"
    end

    test "prompt includes sector and industry" do
      fundamental = build_fundamental(sector: "Technology", industry: "Consumer Electronics")
      prompt = Stocks::AnalysisPromptBuilder.call(ticker: "AAPL", fundamental: fundamental)

      assert_includes prompt, "Technology"
      assert_includes prompt, "Consumer Electronics"
    end

    test "prompt includes key financial metrics" do
      fundamental = build_fundamental(pe: BigDecimal("28.5"), roe: BigDecimal("147.25"))
      prompt = Stocks::AnalysisPromptBuilder.call(ticker: "AAPL", fundamental: fundamental)

      assert_includes prompt, "28.5"
      assert_includes prompt, "147.25"
    end

    test "prompt requests JSON output" do
      fundamental = build_fundamental
      prompt = Stocks::AnalysisPromptBuilder.call(ticker: "AAPL", fundamental: fundamental)

      assert_includes prompt, '"rating"'
      assert_includes prompt, '"executive_summary"'
      assert_includes prompt, '"thesis_breakdown"'
      assert_includes prompt, '"red_flags"'
    end

    test "prompt handles nil fundamentals gracefully" do
      fundamental = build_fundamental(pe: nil, sector: nil, ev_ebitda: nil)
      prompt = Stocks::AnalysisPromptBuilder.call(ticker: "AAPL", fundamental: fundamental)

      assert_includes prompt, "N/A"
      assert_includes prompt, "AAPL"
    end

    test "prompt handles nil fundamental record" do
      prompt = Stocks::AnalysisPromptBuilder.call(ticker: "AAPL", fundamental: nil)

      assert_includes prompt, "AAPL"
      assert_includes prompt, "N/A"
    end
  end
end
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
bin/rails test test/services/stocks/analysis_prompt_builder_test.rb
```

Expected: Failures — `AnalysisPromptBuilder` doesn't exist yet.

- [ ] **Step 3: Create the service** at `app/services/stocks/analysis_prompt_builder.rb`:

```ruby
# frozen_string_literal: true

module Stocks
  # Builds a Gemini prompt for value investment analysis of a single ticker.
  # Embeds available fundamentals and the value investment thesis framework.
  # Returns a prompt string that instructs Gemini to respond with JSON only.
  class AnalysisPromptBuilder
    def self.call(ticker:, fundamental:)
      new(ticker, fundamental).call
    end

    def initialize(ticker, fundamental)
      @ticker      = ticker
      @fundamental = fundamental
    end

    def call
      <<~PROMPT
        You are a Senior Value Investment Analyst specializing in Fundamental Analysis and Portfolio Management. Your objective is to evaluate companies using a strict "Owner Mentality" framework.

        Analyze **#{@ticker}** based on the following data and framework:

        ## Available Fundamentals
        - Sector: #{field(:sector)}
        - Industry: #{field(:industry)}
        - P/E: #{field(:pe)}
        - Forward P/E: #{field(:fwd_pe)}
        - PEG: #{field(:peg)}
        - P/S: #{field(:ps)}
        - P/FCF: #{field(:pfcf)}
        - EV/EBITDA: #{field(:ev_ebitda)}
        - Net Margin: #{pct_field(:net_margin)}
        - ROE: #{pct_field(:roe)}
        - ROIC: #{pct_field(:roic)}
        - Debt/Equity: #{field(:debt_eq)}
        - Sales Y/Y: #{pct_field(:sales_5y)}
        - Sales Q/Q: #{pct_field(:sales_qq)}

        ## Investment Framework

        1. **Business Model & Moat Analysis:**
           - Identify the core business model.
           - Classify as Asset Light (tech, software, intangible-based) or Asset Heavy (manufacturing, energy, intensive CapEx).
           - Evaluate the Economic Moat (Scale, Switching Costs, Network Effect, or Intangibles). If no moat is identified, apply a higher margin of safety.

        2. **Quantitative Health & Solvency (Mandatory):**
           - Debt/Equity < 0.5 is excellent; > 1.0 is a warning sign; > 2.0 indicates high leverage risk (use as proxy for Net Debt/EBITDA when EV/EBITDA is unavailable).
           - Analyze Revenue vs. Earnings: Prioritize revenue stability. If earnings are down due to reinvestment but revenue remains strong, maintain a neutral-to-positive outlook.
           - EV/EBITDA < 15 is reasonable; > 30 warrants scrutiny.

        3. **Valuation & Sentiment:**
           - Analyze P/E in context of asset intensity (higher P/E is acceptable for Asset Light; lower P/E is expected for Asset Heavy).
           - Value Trap Check: If P/E is significantly below industry average, identify the market's reason. Do not assume it is "cheap" without identifying a specific market sentiment bias.
           - Determine Margin of Safety required based on systemic risk and liquidity.

        4. **Portfolio Fit:**
           - Assess potential Sharpe Ratio contribution.
           - Distinguish between growth drivers (Appreciation) and income drivers (Dividends).

        ## Required Output

        Respond with ONLY a JSON object — no markdown fences, no explanation, no text outside the JSON:

        {"rating":"buy","executive_summary":"1-2 sentence verdict.","risk_reward_rating":"Excellent/Good/Fair/Poor — one sentence with key leverage and risk insight.","thesis_breakdown":"3-5 sentence qualitative moat and quantitative valuation analysis.","red_flags":"Comma-separated red flags, or None if clean."}

        Use one of these exact values for rating: buy, hold, sell, watch.
      PROMPT
    end

    private

    def field(attr)
      return "N/A" if @fundamental.nil?
      val = @fundamental.public_send(attr)
      val.present? ? val.to_s : "N/A"
    end

    def pct_field(attr)
      return "N/A" if @fundamental.nil?
      val = @fundamental.public_send(attr)
      val.present? ? "#{val}%" : "N/A"
    end
  end
end
```

- [ ] **Step 4: Run tests to confirm they pass**

```bash
bin/rails test test/services/stocks/analysis_prompt_builder_test.rb
```

Expected: 6 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add app/services/stocks/analysis_prompt_builder.rb \
        test/services/stocks/analysis_prompt_builder_test.rb
git commit -m "feat(stocks): add AnalysisPromptBuilder service"
```

---

### Task 3: SyncStockAnalysisJob

**Files:**
- Create: `app/jobs/stocks/sync_stock_analysis_job.rb`
- Create: `test/jobs/stocks/sync_stock_analysis_job_test.rb`

- [ ] **Step 1: Write failing tests** at `test/jobs/stocks/sync_stock_analysis_job_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

module Stocks
  class SyncStockAnalysisJobTest < ActiveSupport::TestCase
    GEMINI_RESPONSE = JSON.generate({
      "rating"             => "buy",
      "executive_summary"  => "Strong moat with durable cash flows.",
      "risk_reward_rating" => "Good — low leverage, dominant brand.",
      "thesis_breakdown"   => "Apple ecosystem creates switching costs.",
      "red_flags"          => "None"
    })

    def gemini_success_response
      res = Object.new
      res.define_singleton_method(:code) { "200" }
      res.define_singleton_method(:body) { GEMINI_RESPONSE }
      res
    end

    def stub_gemini_http(response)
      fake_http = Object.new
      fake_http.define_singleton_method(:use_ssl=)      { |_| }
      fake_http.define_singleton_method(:open_timeout=) { |_| }
      fake_http.define_singleton_method(:read_timeout=) { |_| }
      fake_http.define_singleton_method(:request)       { |_req| response }
      Net::HTTP.stub(:new, fake_http) { yield }
    end

    setup do
      @user = users(:one)
      @user.update!(gemini_api_key: "AIzaTestKey123")
    end

    test "skips user without Gemini key" do
      @user.update!(gemini_api_key: nil)
      called = false
      Ai::GeminiService.stub(:new, ->(_) { called = true; raise "should not call" }) do
        Stocks::SyncStockAnalysisJob.new.perform(@user.id, ["AAPL"])
      end
      assert_not called
    end

    test "upserts analysis for each ticker" do
      fundamental = stock_fundamentals(:aapl)

      StockFundamental.stub(:for_tickers, { "AAPL" => fundamental }) do
        stub_gemini_http(gemini_success_response) do
          Stocks::SyncStockAnalysisJob.new.perform(@user.id, ["AAPL"])
        end
      end

      analysis = StockAnalysis.find_by!(user: @user, ticker: "AAPL")
      assert_equal "buy",                               analysis.rating
      assert_equal "Strong moat with durable cash flows.", analysis.executive_summary
      assert_equal "Good — low leverage, dominant brand.", analysis.risk_reward_rating
      assert_equal "Apple ecosystem creates switching costs.", analysis.thesis_breakdown
      assert_equal "None",                              analysis.red_flags
      assert_not_nil analysis.analyzed_at
    end

    test "skips ticker on Gemini error and continues with remaining tickers" do
      fundamentals = {
        "AAPL" => stock_fundamentals(:aapl),
        "MSFT" => StockFundamental.new(ticker: "MSFT", fetched_at: Time.current)
      }
      call_count = 0

      StockFundamental.stub(:for_tickers, fundamentals) do
        fake_http = Object.new
        fake_http.define_singleton_method(:use_ssl=)      { |_| }
        fake_http.define_singleton_method(:open_timeout=) { |_| }
        fake_http.define_singleton_method(:read_timeout=) { |_| }
        fake_http.define_singleton_method(:request) do |_req|
          call_count += 1
          res = Object.new
          res.define_singleton_method(:code) { call_count == 1 ? "429" : "200" }
          res.define_singleton_method(:body) { call_count == 1 ? "{}" : SyncStockAnalysisJobTest::GEMINI_RESPONSE }
          res
        end
        Net::HTTP.stub(:new, fake_http) do
          Stocks::SyncStockAnalysisJob.new.perform(@user.id, ["AAPL", "MSFT"])
        end
      end

      assert_nil StockAnalysis.find_by(user: @user, ticker: "AAPL")
      assert_not_nil StockAnalysis.find_by(user: @user, ticker: "MSFT")
    end

    test "skips ticker when Gemini response is not valid JSON" do
      StockFundamental.stub(:for_tickers, { "AAPL" => stock_fundamentals(:aapl) }) do
        bad_res = Object.new
        bad_res.define_singleton_method(:code) { "200" }
        bad_res.define_singleton_method(:body) { JSON.generate({ "candidates" => [{ "content" => { "parts" => [{ "text" => "not json at all" }] } }] }) }

        fake_http = Object.new
        fake_http.define_singleton_method(:use_ssl=)      { |_| }
        fake_http.define_singleton_method(:open_timeout=) { |_| }
        fake_http.define_singleton_method(:read_timeout=) { |_| }
        fake_http.define_singleton_method(:request) { |_req| bad_res }

        Net::HTTP.stub(:new, fake_http) do
          assert_nothing_raised { Stocks::SyncStockAnalysisJob.new.perform(@user.id, ["AAPL"]) }
        end
      end

      assert_nil StockAnalysis.find_by(user: @user, ticker: "AAPL")
    end
  end
end
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
bin/rails test test/jobs/stocks/sync_stock_analysis_job_test.rb
```

Expected: Failures — `SyncStockAnalysisJob` doesn't exist yet.

- [ ] **Step 3: Create the job** at `app/jobs/stocks/sync_stock_analysis_job.rb`:

```ruby
# frozen_string_literal: true

module Stocks
  # Generates AI investment analysis for a list of tickers using the user's Gemini key.
  # Results are upserted into stock_analyses (one record per user+ticker).
  # Skips silently if the user has no Gemini key configured.
  class SyncStockAnalysisJob < ApplicationJob
    queue_as :default

    RATE_LIMIT_DELAY = 1.0 # seconds between Gemini requests

    def perform(user_id, tickers)
      user = User.find(user_id)
      return unless user.gemini_api_key_configured?

      gemini    = Ai::GeminiService.new(api_key: user.gemini_api_key)
      fundamentals = StockFundamental.for_tickers(tickers)
      now = Time.current

      tickers.each_with_index do |ticker, i|
        sleep(RATE_LIMIT_DELAY) if i > 0

        prompt = Stocks::AnalysisPromptBuilder.call(
          ticker:      ticker,
          fundamental: fundamentals[ticker]
        )

        begin
          raw = gemini.generate(prompt: prompt)
          parsed = JSON.parse(raw)

          StockAnalysis.upsert(
            {
              user_id:            user.id,
              ticker:             ticker,
              rating:             parsed["rating"].to_s.downcase.presence || "watch",
              executive_summary:  parsed["executive_summary"],
              risk_reward_rating: parsed["risk_reward_rating"],
              thesis_breakdown:   parsed["thesis_breakdown"],
              red_flags:          parsed["red_flags"],
              analyzed_at:        now,
              created_at:         now,
              updated_at:         now
            },
            unique_by: [:user_id, :ticker],
            update_only: %i[rating executive_summary risk_reward_rating thesis_breakdown red_flags analyzed_at updated_at]
          )

          Rails.logger.info("[Stocks::SyncStockAnalysisJob] #{ticker}: #{parsed['rating']}")
        rescue Ai::Error => e
          Rails.logger.error("[Stocks::SyncStockAnalysisJob] #{ticker} Gemini error: #{e.message}")
        rescue JSON::ParserError => e
          Rails.logger.error("[Stocks::SyncStockAnalysisJob] #{ticker} JSON parse error: #{e.message}")
        end
      end

      Rails.logger.info("[Stocks::SyncStockAnalysisJob] Completed #{tickers.size} tickers for user #{user_id}")
    end
  end
end
```

- [ ] **Step 4: Run tests to confirm they pass**

```bash
bin/rails test test/jobs/stocks/sync_stock_analysis_job_test.rb
```

Expected: 4 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add app/jobs/stocks/sync_stock_analysis_job.rb \
        test/jobs/stocks/sync_stock_analysis_job_test.rb
git commit -m "feat(stocks): add SyncStockAnalysisJob with Gemini integration"
```

---

### Task 4: Controller action + routes

**Files:**
- Modify: `config/routes.rb`
- Modify: `app/controllers/stocks_controller.rb`

- [ ] **Step 1: Add route** in `config/routes.rb`

After the line `post "stocks/sync_watchlist", to: "stocks#sync_watchlist", as: :stocks_watchlist_sync`, add:

```ruby
  post "stocks/sync_analysis", to: "stocks#sync_analysis", as: :stocks_sync_analysis
```

- [ ] **Step 2: Add `sync_analysis` action and load analyses in controller**

In `app/controllers/stocks_controller.rb`:

**a)** In the `when "valuations"` block, add analyses loading. Replace:

```ruby
    when "valuations"
      all_positions = Stocks::PositionStateService.call(stock_portfolio: @stock_portfolio)
      @positions    = all_positions.select(&:open?)
      @fundamentals = StockFundamental.for_tickers(@positions.map(&:ticker))
```

With:

```ruby
    when "valuations"
      all_positions = Stocks::PositionStateService.call(stock_portfolio: @stock_portfolio)
      @positions    = all_positions.select(&:open?)
      tickers       = @positions.map(&:ticker)
      @fundamentals = StockFundamental.for_tickers(tickers)
      @analyses     = StockAnalysis.for_user_and_tickers(current_user, tickers)
```

**b)** In the `when "watchlist"` block, add analyses loading. Replace:

```ruby
    when "watchlist"
      @watchlist_tickers = current_user.watchlist_tickers.ordered
      @fundamentals      = StockFundamental.for_tickers(@watchlist_tickers.pluck(:ticker))
```

With:

```ruby
    when "watchlist"
      @watchlist_tickers = current_user.watchlist_tickers.ordered
      tickers            = @watchlist_tickers.pluck(:ticker)
      @fundamentals      = StockFundamental.for_tickers(tickers)
      @analyses          = StockAnalysis.for_user_and_tickers(current_user, tickers)
```

**c)** Add the `sync_analysis` action after `sync_watchlist`:

```ruby
  def sync_analysis
    tickers = collect_analysis_tickers
    if tickers.any?
      Stocks::SyncStockAnalysisJob.perform_later(current_user.id, tickers)
      notice = "Analysis started — refresh in a moment to see ratings."
    else
      notice = "No tickers to analyze."
    end
    redirect_back fallback_location: stocks_path, notice: notice
  end
```

**d)** Add the private helper at the bottom of the `private` section:

```ruby
  def collect_analysis_tickers
    portfolio = StockPortfolio.find_or_create_default_for(current_user)
    open_tickers = Stocks::PositionStateService.call(stock_portfolio: portfolio)
                    .select(&:open?).map(&:ticker)
    watchlist_tickers = current_user.watchlist_tickers.pluck(:ticker)
    (open_tickers + watchlist_tickers).uniq
  end
```

- [ ] **Step 3: Run full test suite to catch regressions**

```bash
bin/rails test
```

Expected: All tests pass. If controller tests reference the `valuations` or `watchlist` setup, they may need `@analyses` — check and fix any failures.

- [ ] **Step 4: Commit**

```bash
git add config/routes.rb app/controllers/stocks_controller.rb
git commit -m "feat(stocks): add sync_analysis route/action and load analyses in controller"
```

---

### Task 5: View update — rating badges + Analyze button

**Files:**
- Modify: `app/views/stocks/_fundamentals_table.html.erb`

The partial currently receives `tickers:`, `fundamentals:`, `sync_url:`, `watchlist_items:`. We add two new optional locals: `analyses:` (default `{}`) and `analyze_url:` (default `nil`).

The AI Rating column logic:
- If `analysis` exists for the ticker → show a colored rating badge
- Else if user has Gemini key → show `—` (pending, waiting for analysis)
- Else → show "Configure AI" link (existing behavior)

Rating badge colors:
- `buy`   → `bg-emerald-100 text-emerald-800`
- `hold`  → `bg-amber-100 text-amber-800`
- `sell`  → `bg-red-100 text-red-800`
- `watch` → `bg-slate-100 text-slate-700`

- [ ] **Step 1: Replace the entire `_fundamentals_table.html.erb`**

```erb
<%# locals: (tickers:, fundamentals:, sync_url:, watchlist_items: nil, analyze_url: nil, analyses: {}) %>
<% last_synced = fundamentals.values.map(&:fetched_at).min %>
<div class="mb-4 flex items-center justify-between">
  <p class="text-xs text-slate-500">
    <% if last_synced %>
      Last synced <%= time_ago_in_words(last_synced) %> ago · "—" means no data available for that ticker
    <% else %>
      No data yet — click Sync to fetch fundamentals from Finviz
    <% end %>
  </p>
  <div class="flex items-center gap-2">
    <%= button_to "Sync now", sync_url,
          method: :post,
          class: "rounded-md bg-slate-800 px-3 py-1.5 text-sm font-medium text-white hover:bg-slate-700 focus:outline-none focus:ring-2 focus:ring-slate-500" %>
    <% if analyze_url && current_user.gemini_api_key_configured? %>
      <%= button_to "Analyze", analyze_url,
            method: :post,
            class: "rounded-md bg-indigo-600 px-3 py-1.5 text-sm font-medium text-white hover:bg-indigo-500 focus:outline-none focus:ring-2 focus:ring-indigo-500" %>
    <% end %>
  </div>
</div>

<%= render DataTableComponent.new(columns: [
  { label: "Ticker",     classes: "text-left" },
  { label: "AI Rating",  classes: "text-center" },
  { label: "Sector",     classes: "text-left" },
  { label: "P/E",        classes: "text-right" },
  { label: "Fwd P/E",   classes: "text-right" },
  { label: "PEG",        classes: "text-right" },
  { label: "P/S",        classes: "text-right" },
  { label: "P/FCF",      classes: "text-right" },
  { label: "EV/EBITDA",  classes: "text-right" },
  { label: "Net Margin", classes: "text-right" },
  { label: "ROE",        classes: "text-right" },
  { label: "ROIC",       classes: "text-right" },
  { label: "Debt/Eq",    classes: "text-right" },
  { label: "Sales Y/Y",  classes: "text-right" },
  { label: "Sales Q/Q",  classes: "text-right" },
  *(watchlist_items ? [{ label: "", classes: "text-right" }] : [])
]) do |table| %>
  <% tickers.each do |ticker| %>
    <% f        = fundamentals[ticker] %>
    <% analysis = analyses[ticker] %>
    <% table.with_row do %>
      <td class="whitespace-nowrap px-6 py-4 text-sm font-semibold text-slate-900"><%= ticker %></td>
      <td class="whitespace-nowrap px-6 py-4 text-center text-sm">
        <% if analysis %>
          <% badge_class = case analysis.rating
             when "buy"   then "bg-emerald-100 text-emerald-800"
             when "hold"  then "bg-amber-100 text-amber-800"
             when "sell"  then "bg-red-100 text-red-800"
             else              "bg-slate-100 text-slate-700"
             end %>
          <span class="inline-flex items-center rounded-full px-2 py-0.5 text-xs font-semibold uppercase tracking-wide <%= badge_class %>">
            <%= analysis.rating %>
          </span>
        <% elsif current_user.gemini_api_key_configured? %>
          <span class="text-slate-400">—</span>
        <% else %>
          <%= link_to "Configure AI", settings_path,
                class: "text-xs font-medium text-indigo-600 hover:text-indigo-800 underline underline-offset-2" %>
        <% end %>
      </td>
      <td class="whitespace-nowrap px-6 py-4 text-sm text-slate-500"><%= f&.sector || "—" %></td>
      <td class="whitespace-nowrap px-6 py-4 text-right text-sm text-slate-700"><%= f&.pe     ? number_with_precision(f.pe,     precision: 1) : "—" %></td>
      <td class="whitespace-nowrap px-6 py-4 text-right text-sm text-slate-700"><%= f&.fwd_pe ? number_with_precision(f.fwd_pe, precision: 1) : "—" %></td>
      <td class="whitespace-nowrap px-6 py-4 text-right text-sm text-slate-700"><%= f&.peg    ? number_with_precision(f.peg,    precision: 2) : "—" %></td>
      <td class="whitespace-nowrap px-6 py-4 text-right text-sm text-slate-700"><%= f&.ps     ? number_with_precision(f.ps,     precision: 1) : "—" %></td>
      <td class="whitespace-nowrap px-6 py-4 text-right text-sm text-slate-700"><%= f&.pfcf   ? number_with_precision(f.pfcf,   precision: 1) : "—" %></td>
      <td class="whitespace-nowrap px-6 py-4 text-right text-sm text-slate-700"><%= f&.ev_ebitda ? number_with_precision(f.ev_ebitda, precision: 1) : "—" %></td>
      <td class="whitespace-nowrap px-6 py-4 text-right text-sm <%= f&.net_margin ? (f.net_margin >= 0 ? 'text-emerald-600' : 'text-red-600') : 'text-slate-500' %>">
        <%= f&.net_margin ? number_to_percentage(f.net_margin, precision: 1) : "—" %>
      </td>
      <td class="whitespace-nowrap px-6 py-4 text-right text-sm <%= f&.roe ? (f.roe >= 0 ? 'text-emerald-600' : 'text-red-600') : 'text-slate-500' %>">
        <%= f&.roe ? number_to_percentage(f.roe, precision: 1) : "—" %>
      </td>
      <td class="whitespace-nowrap px-6 py-4 text-right text-sm <%= f&.roic ? (f.roic >= 0 ? 'text-emerald-600' : 'text-red-600') : 'text-slate-500' %>">
        <%= f&.roic ? number_to_percentage(f.roic, precision: 1) : "—" %>
      </td>
      <td class="whitespace-nowrap px-6 py-4 text-right text-sm text-slate-700"><%= f&.debt_eq  ? number_with_precision(f.debt_eq,  precision: 2) : "—" %></td>
      <td class="whitespace-nowrap px-6 py-4 text-right text-sm <%= f&.sales_5y ? (f.sales_5y >= 0 ? 'text-emerald-600' : 'text-red-600') : 'text-slate-500' %>">
        <%= f&.sales_5y ? number_to_percentage(f.sales_5y, precision: 1) : "—" %>
      </td>
      <td class="whitespace-nowrap px-6 py-4 text-right text-sm <%= f&.sales_qq ? (f.sales_qq >= 0 ? 'text-emerald-600' : 'text-red-600') : 'text-slate-500' %>">
        <%= f&.sales_qq ? number_to_percentage(f.sales_qq, precision: 1) : "—" %>
      </td>
      <% if watchlist_items %>
        <td class="whitespace-nowrap px-6 py-4 text-right">
          <%= button_to "Remove", stocks_watchlist_item_path(watchlist_items[ticker]),
                method: :delete,
                class: "text-xs font-medium text-red-500 hover:text-red-700" %>
        </td>
      <% end %>
    <% end %>
  <% end %>
<% end %>
```

- [ ] **Step 2: Update the valuations partial render to pass new locals**

Find where `_fundamentals_table` is rendered in `app/views/stocks/index.html.erb` for the valuations view. It should currently look like:

```erb
<%= render "fundamentals_table", tickers: ..., fundamentals: @fundamentals, sync_url: stocks_sync_fundamentals_path(...), watchlist_items: nil %>
```

Add `analyses: @analyses, analyze_url: stocks_sync_analysis_path` to that render call.

Similarly for the watchlist render, add `analyses: @analyses, analyze_url: stocks_sync_analysis_path`.

**To find the exact lines:** run `grep -n "fundamentals_table" app/views/stocks/index.html.erb` and read the relevant lines, then edit precisely.

- [ ] **Step 3: Run full test suite**

```bash
bin/rails test
```

Expected: All tests pass.

- [ ] **Step 4: Commit**

```bash
git add app/views/stocks/_fundamentals_table.html.erb \
        app/views/stocks/index.html.erb
git commit -m "feat(stocks): show AI rating badges and Analyze button in fundamentals table"
```

---

### Task 6: Final smoke test + rubocop

- [ ] **Step 1: Run full test suite**

```bash
bin/rails test
```

Expected: All tests pass, 0 failures, 0 errors.

- [ ] **Step 2: Run rubocop on new files**

```bash
bundle exec rubocop \
  app/models/stock_analysis.rb \
  app/services/stocks/analysis_prompt_builder.rb \
  app/jobs/stocks/sync_stock_analysis_job.rb \
  app/controllers/stocks_controller.rb
```

- [ ] **Step 3: Auto-fix any offenses**

```bash
bundle exec rubocop -a \
  app/models/stock_analysis.rb \
  app/services/stocks/analysis_prompt_builder.rb \
  app/jobs/stocks/sync_stock_analysis_job.rb \
  app/controllers/stocks_controller.rb
```

- [ ] **Step 4: Commit lint fixes if any**

```bash
git add app/models/stock_analysis.rb \
        app/services/stocks/analysis_prompt_builder.rb \
        app/jobs/stocks/sync_stock_analysis_job.rb \
        app/controllers/stocks_controller.rb
git commit -m "style: rubocop fixes for AI analysis feature"
```
