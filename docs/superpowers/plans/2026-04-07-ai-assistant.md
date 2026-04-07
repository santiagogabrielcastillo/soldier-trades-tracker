# AI Assistant Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a BYOK Gemini AI assistant with a floating chat panel, per-user encrypted API key storage, and full portfolio context (futures, spot, stocks, watchlist).

**Architecture:** Plain Ruby service objects call the Gemini REST API via `Net::HTTP` (same pattern as exchange clients). A Stimulus controller manages the floating panel and POSTs to `AiController#chat`. API keys are stored encrypted on the `users` table using Rails 7.2 `encrypts`.

**Tech Stack:** Rails 7.2, Ruby Net::HTTP, Rails 7.2 `encrypts`, Stimulus, Tailwind CSS, Minitest with `Net::HTTP.stub`.

---

## File Map

| File | Action | Purpose |
|------|--------|---------|
| `db/migrate/TIMESTAMP_add_gemini_api_key_to_users.rb` | Create | Adds `gemini_api_key` encrypted column |
| `app/models/user.rb` | Modify | Add `encrypts :gemini_api_key`, two helpers |
| `app/services/ai/errors.rb` | Create | `Ai::Error`, `Ai::RateLimitError`, `Ai::InvalidKeyError`, `Ai::ServiceError` |
| `app/services/ai/gemini_service.rb` | Create | Raw Net::HTTP call to Gemini REST API |
| `app/services/ai/portfolio_context_builder.rb` | Create | Assembles all portfolio data into markdown prompt |
| `app/controllers/ai_controller.rb` | Create | `chat` and `test_key` JSON actions |
| `app/controllers/settings_controller.rb` | Modify | Add `update_ai_key` and `remove_ai_key` actions |
| `config/routes.rb` | Modify | Add AI routes + settings AI key routes |
| `app/views/settings/show.html.erb` | Modify | Add AI Assistant fieldset |
| `app/javascript/controllers/ai_chat_controller.js` | Create | Stimulus controller for floating panel |
| `app/views/layouts/application.html.erb` | Modify | Mount floating button + panel in authenticated layout |
| `test/models/user_test.rb` | Modify | Tests for new helpers |
| `test/services/ai/gemini_service_test.rb` | Create | Unit tests with Net::HTTP stubs |
| `test/services/ai/portfolio_context_builder_test.rb` | Create | Unit tests with service stubs |
| `test/controllers/ai_controller_test.rb` | Create | Integration tests |
| `test/controllers/settings_controller_test.rb` | Modify | Tests for ai_key actions |

---

## Task 1: Migration + User model

**Files:**
- Create: `db/migrate/TIMESTAMP_add_gemini_api_key_to_users.rb`
- Modify: `app/models/user.rb`
- Modify: `test/models/user_test.rb`

- [ ] **Step 1.1: Write the failing tests**

Append to `test/models/user_test.rb`:

```ruby
test "gemini_api_key_configured? returns false when key is nil" do
  user = User.new(email: "ai@example.com", password: "password")
  assert_equal false, user.gemini_api_key_configured?
end

test "gemini_api_key_configured? returns true when key is set" do
  user = users(:one)
  user.gemini_api_key = "AIzaSyTestKey12345678"
  assert_equal true, user.gemini_api_key_configured?
end

test "gemini_api_key_masked returns nil when key is blank" do
  user = User.new(email: "ai@example.com", password: "password")
  assert_nil user.gemini_api_key_masked
end

test "gemini_api_key_masked returns masked string when key is set" do
  user = users(:one)
  user.gemini_api_key = "AIzaSyTestKey12345678"
  assert_equal "AIza...5678", user.gemini_api_key_masked
end
```

- [ ] **Step 1.2: Run the tests to confirm they fail**

```bash
bin/rails test test/models/user_test.rb
```

Expected: 4 failures/errors — `undefined method 'gemini_api_key_configured?'` or similar.

- [ ] **Step 1.3: Generate the migration**

```bash
bin/rails generate migration AddGeminiApiKeyToUsers gemini_api_key:text
```

Open the generated file (will be in `db/migrate/`) and verify it looks like:

```ruby
class AddGeminiApiKeyToUsers < ActiveRecord::Migration[7.2]
  def change
    add_column :users, :gemini_api_key, :text
  end
end
```

- [ ] **Step 1.4: Run the migration**

```bash
bin/rails db:migrate
bin/rails db:migrate RAILS_ENV=test
```

Expected: `== AddGeminiApiKeyToUsers: migrated`

- [ ] **Step 1.5: Add encryption and helpers to User model**

In `app/models/user.rb`, after the `has_secure_password` line, add:

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

- [ ] **Step 1.6: Run the tests to confirm they pass**

```bash
bin/rails test test/models/user_test.rb
```

Expected: All tests pass (4 new + 1 existing).

- [ ] **Step 1.7: Commit**

```bash
git add db/migrate/ app/models/user.rb test/models/user_test.rb
git commit -m "feat(ai): add encrypted gemini_api_key to User model"
```

---

## Task 2: AI error classes

**Files:**
- Create: `app/services/ai/errors.rb`

- [ ] **Step 2.1: Create the error module**

Create `app/services/ai/errors.rb`:

```ruby
# frozen_string_literal: true

module Ai
  class Error < StandardError; end
  class RateLimitError < Error; end
  class InvalidKeyError < Error; end
  class ServiceError < Error; end
end
```

- [ ] **Step 2.2: Commit**

```bash
git add app/services/ai/errors.rb
git commit -m "feat(ai): add AI error classes"
```

---

## Task 3: Gemini service

**Files:**
- Create: `app/services/ai/gemini_service.rb`
- Create: `test/services/ai/gemini_service_test.rb`

- [ ] **Step 3.1: Write the failing tests**

Create `test/services/ai/gemini_service_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class Ai::GeminiServiceTest < ActiveSupport::TestCase
  setup do
    @service = Ai::GeminiService.new(api_key: "AIzaTestKey")
  end

  test "generate returns response text on success" do
    body = JSON.generate({
      "candidates" => [
        { "content" => { "parts" => [{ "text" => "Hello from Gemini" }] } }
      ]
    })
    stub_http_response(code: "200", body: body) do
      result = @service.generate(prompt: "Say hello")
      assert_equal "Hello from Gemini", result
    end
  end

  test "generate raises RateLimitError on 429" do
    body = JSON.generate({ "error" => { "code" => 429, "message" => "Resource exhausted" } })
    stub_http_response(code: "429", body: body) do
      assert_raises(Ai::RateLimitError) { @service.generate(prompt: "test") }
    end
  end

  test "generate raises InvalidKeyError on 401" do
    body = JSON.generate({ "error" => { "code" => 401, "message" => "API key not valid" } })
    stub_http_response(code: "401", body: body) do
      assert_raises(Ai::InvalidKeyError) { @service.generate(prompt: "test") }
    end
  end

  test "generate raises InvalidKeyError on 403" do
    body = JSON.generate({ "error" => { "code" => 403, "message" => "Forbidden" } })
    stub_http_response(code: "403", body: body) do
      assert_raises(Ai::InvalidKeyError) { @service.generate(prompt: "test") }
    end
  end

  test "generate raises InvalidKeyError on 400" do
    body = JSON.generate({ "error" => { "code" => 400, "message" => "Bad Request" } })
    stub_http_response(code: "400", body: body) do
      assert_raises(Ai::InvalidKeyError) { @service.generate(prompt: "test") }
    end
  end

  test "generate raises ServiceError on 500" do
    stub_http_response(code: "500", body: "Internal Server Error") do
      assert_raises(Ai::ServiceError) { @service.generate(prompt: "test") }
    end
  end

  test "generate raises ServiceError on empty body" do
    stub_http_response(code: "200", body: "") do
      assert_raises(Ai::ServiceError) { @service.generate(prompt: "test") }
    end
  end

  test "generate raises ServiceError on timeout" do
    stub_http_timeout(Net::ReadTimeout) do
      assert_raises(Ai::ServiceError) { @service.generate(prompt: "test") }
    end
  end

  private

  def fake_response(code:, body:)
    res = Object.new
    res.define_singleton_method(:code) { code.to_s }
    res.define_singleton_method(:body) { body }
    res
  end

  def stub_http_response(code:, body:)
    response = fake_response(code: code, body: body)
    fake = Object.new
    fake.define_singleton_method(:use_ssl=) { |_| }
    fake.define_singleton_method(:open_timeout=) { |_| }
    fake.define_singleton_method(:read_timeout=) { |_| }
    fake.define_singleton_method(:request) { |_req| response }
    Net::HTTP.stub(:new, fake) { yield }
  end

  def stub_http_timeout(exception_klass)
    fake = Object.new
    fake.define_singleton_method(:use_ssl=) { |_| }
    fake.define_singleton_method(:open_timeout=) { |_| }
    fake.define_singleton_method(:read_timeout=) { |_| }
    fake.define_singleton_method(:request) { |_req| raise exception_klass.new("timeout") }
    Net::HTTP.stub(:new, fake) { yield }
  end
end
```

- [ ] **Step 3.2: Run tests to confirm they fail**

```bash
bin/rails test test/services/ai/gemini_service_test.rb
```

Expected: Error — `uninitialized constant Ai::GeminiService`.

- [ ] **Step 3.3: Create the service**

Create `app/services/ai/gemini_service.rb`:

```ruby
# frozen_string_literal: true

require "net/http"
require "json"

module Ai
  class GeminiService
    ENDPOINT = "https://generativelanguage.googleapis.com"
    MODEL    = "gemini-2.5-flash"

    def initialize(api_key:)
      @api_key = api_key
    end

    def generate(prompt:)
      uri = URI("#{ENDPOINT}/v1beta/models/#{MODEL}:generateContent")
      uri.query = URI.encode_www_form("key" => @api_key)

      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"
      request.body = JSON.generate({
        "contents" => [
          { "parts" => [{ "text" => prompt }] }
        ]
      })

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 10
      http.read_timeout = 30

      response = http.request(request)
      parse_response!(response)
    rescue Net::OpenTimeout, Net::ReadTimeout, Timeout::Error => e
      raise Ai::ServiceError, "Gemini request timed out: #{e.message}"
    end

    private

    def parse_response!(response)
      code = response.code.to_s

      case code
      when "200"
        parse_success!(response.body)
      when "429"
        raise Ai::RateLimitError, "Gemini rate limit exceeded"
      when "400", "401", "403"
        raise Ai::InvalidKeyError, "Gemini API key invalid or unauthorized"
      else
        raise Ai::ServiceError, "Gemini API returned #{code}"
      end
    end

    def parse_success!(body)
      raise Ai::ServiceError, "Gemini returned empty response" if body.blank?

      parsed = JSON.parse(body)
      text = parsed.dig("candidates", 0, "content", "parts", 0, "text")
      raise Ai::ServiceError, "Gemini response missing text field" if text.nil?
      text
    rescue JSON::ParserError => e
      raise Ai::ServiceError, "Gemini returned non-JSON response: #{e.message}"
    end
  end
end
```

- [ ] **Step 3.4: Run tests to confirm they pass**

```bash
bin/rails test test/services/ai/gemini_service_test.rb
```

Expected: 8 tests, 0 failures.

- [ ] **Step 3.5: Commit**

```bash
git add app/services/ai/gemini_service.rb test/services/ai/gemini_service_test.rb
git commit -m "feat(ai): add GeminiService with Net::HTTP and typed error handling"
```

---

## Task 4: Portfolio context builder

**Files:**
- Create: `app/services/ai/portfolio_context_builder.rb`
- Create: `test/services/ai/portfolio_context_builder_test.rb`

- [ ] **Step 4.1: Write the failing tests**

Create `test/services/ai/portfolio_context_builder_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class Ai::PortfolioContextBuilderTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @builder = Ai::PortfolioContextBuilder.new(user: @user)
  end

  test "call returns a non-empty string" do
    stub_empty_services do
      result = @builder.call
      assert_instance_of String, result
      assert result.length > 0
    end
  end

  test "includes date header" do
    stub_empty_services do
      result = @builder.call
      assert_match(/Portfolio context as of/, result)
    end
  end

  test "futures section says no data when no positions" do
    stub_empty_services do
      result = @builder.call
      assert_match(/Crypto Futures/, result)
      assert_match(/No futures positions/, result)
    end
  end

  test "spot section says no data when no positions" do
    stub_empty_services do
      result = @builder.call
      assert_match(/Spot Holdings/, result)
      assert_match(/No spot positions/, result)
    end
  end

  test "stocks section says no data when no positions" do
    stub_empty_services do
      result = @builder.call
      assert_match(/Stock Portfolio/, result)
      assert_match(/No stock positions/, result)
    end
  end

  test "futures section includes position data when positions exist" do
    FakePos = Struct.new(:symbol, :position_side, :entry_price, :net_pl, :open_quantity,
                         :open?, :roi_percent, :leverage, :open_at, :close_at, keyword_init: true)
    open_pos = FakePos.new(
      symbol: "BTC-USDT", position_side: "LONG", entry_price: BigDecimal("50000"),
      net_pl: BigDecimal("1000"), open_quantity: BigDecimal("0.02"),
      open?: true, roi_percent: nil, leverage: 10, open_at: 1.day.ago, close_at: nil
    )

    fake_rel = Object.new
    fake_rel.define_singleton_method(:ordered_for_display) do
      ordered = Object.new
      ordered.define_singleton_method(:to_a) { [open_pos] }
      ordered
    end

    Position.stub(:for_user, ->(_user) { fake_rel }) do
      stub_empty_services(skip_futures: true) do
        result = @builder.call
        assert_match(/BTC-USDT/, result)
        assert_match(/LONG/, result)
      end
    end
  end

  test "watchlist section includes ticker when watchlist has items" do
    ticker = WatchlistTicker.new(ticker: "AAPL")
    @user.stub(:watchlist_tickers, ->{ mock_rel = Object.new; mock_rel.define_singleton_method(:ordered) { [ticker] }; mock_rel }) do
      StockFundamental.stub(:for_tickers, ->(_tickers) { {} }) do
        stub_empty_services do
          result = @builder.call
          assert_match(/AAPL/, result)
        end
      end
    end
  end

  private

  def stub_empty_services(skip_futures: false)
    empty_ordered = Object.new
    empty_ordered.define_singleton_method(:to_a) { [] }
    empty_rel = Object.new
    empty_rel.define_singleton_method(:ordered_for_display) { empty_ordered }

    spot_stub = ->(_opts) { [] }
    stocks_stub = ->(_opts) { [] }
    allocation_stub = ->(_opts) {
      Allocations::SummaryService::Result.new(buckets: [], total_usd: BigDecimal("0"), unassigned_sources: [])
    }
    watchlist_stub = Object.new
    watchlist_stub.define_singleton_method(:ordered) { [] }

    if skip_futures
      spot_stub_v = spot_stub
      stocks_stub_v = stocks_stub
      allocation_stub_v = allocation_stub
      Spot::PositionStateService.stub(:call, spot_stub_v) do
        Stocks::PositionStateService.stub(:call, stocks_stub_v) do
          Allocations::SummaryService.stub(:call, allocation_stub_v) do
            @user.stub(:watchlist_tickers, watchlist_stub) do
              yield
            end
          end
        end
      end
    else
      Position.stub(:for_user, ->(_user) { empty_rel }) do
        Spot::PositionStateService.stub(:call, spot_stub) do
          Stocks::PositionStateService.stub(:call, stocks_stub) do
            Allocations::SummaryService.stub(:call, allocation_stub) do
              @user.stub(:watchlist_tickers, watchlist_stub) do
                yield
              end
            end
          end
        end
      end
    end
  end
end
```

- [ ] **Step 4.2: Run tests to confirm they fail**

```bash
bin/rails test test/services/ai/portfolio_context_builder_test.rb
```

Expected: Error — `uninitialized constant Ai::PortfolioContextBuilder`.

- [ ] **Step 4.3: Create the service**

Create `app/services/ai/portfolio_context_builder.rb`:

```ruby
# frozen_string_literal: true

module Ai
  class PortfolioContextBuilder
    CLOSED_POSITIONS_LIMIT = 50

    def initialize(user:)
      @user = user
    end

    def call
      sections = []
      sections << "Portfolio context as of #{Date.today.strftime('%B %d, %Y')}:"
      sections << futures_section
      sections << spot_section
      sections << stocks_section
      sections << allocation_section
      sections << watchlist_section
      sections.join("\n\n")
    end

    private

    def futures_section
      all_positions = Position.for_user(@user).ordered_for_display.to_a
      open_positions = all_positions.select(&:open?)
      closed_positions = all_positions.reject(&:open?).first(CLOSED_POSITIONS_LIMIT)
      positions = open_positions + closed_positions

      lines = ["## Crypto Futures Positions"]
      if positions.empty?
        lines << "No futures positions found."
        return lines.join("\n")
      end

      lines << "| Symbol | Side | Status | Entry Price | Net P&L | ROI% | Leverage |"
      lines << "|--------|------|--------|-------------|---------|------|----------|"
      positions.each do |p|
        status = p.open? ? "Open" : "Closed"
        entry = p.entry_price ? "$#{p.entry_price.round(4)}" : "—"
        pl = p.net_pl ? "$#{p.net_pl.round(2)}" : "—"
        roi = p.roi_percent ? "#{p.roi_percent}%" : "—"
        lev = p.leverage ? "#{p.leverage}x" : "—"
        lines << "| #{p.symbol} | #{p.position_side} | #{status} | #{entry} | #{pl} | #{roi} | #{lev} |"
      end
      lines.join("\n")
    end

    def spot_section
      spot_account = SpotAccount.find_or_create_default_for(@user)
      positions = Spot::PositionStateService.call(spot_account: spot_account)
      open_positions = positions.select(&:open?)

      lines = ["## Spot Holdings"]
      if open_positions.empty?
        lines << "No spot positions found."
        return lines.join("\n")
      end

      lines << "| Token | Balance | Net USD Invested | Breakeven |"
      lines << "|-------|---------|-----------------|-----------|"
      open_positions.each do |p|
        bal = p.balance.round(6)
        invested = p.net_usd_invested ? "$#{p.net_usd_invested.round(2)}" : "—"
        be = p.breakeven ? "$#{p.breakeven.round(4)}" : "—"
        lines << "| #{p.token} | #{bal} | #{invested} | #{be} |"
      end
      lines.join("\n")
    end

    def stocks_section
      stock_portfolio = StockPortfolio.find_or_create_default_for(@user)
      positions = Stocks::PositionStateService.call(stock_portfolio: stock_portfolio)
      open_positions = positions.select(&:open?)

      lines = ["## Stock Portfolio"]
      if open_positions.empty?
        lines << "No stock positions found."
        return lines.join("\n")
      end

      lines << "| Ticker | Shares | Net USD Invested | Breakeven |"
      lines << "|--------|--------|-----------------|-----------|"
      open_positions.each do |p|
        shares = p.shares.round(4)
        invested = p.net_usd_invested ? "$#{p.net_usd_invested.round(2)}" : "—"
        be = p.breakeven ? "$#{p.breakeven.round(4)}" : "—"
        lines << "| #{p.ticker} | #{shares} | #{invested} | #{be} |"
      end
      lines.join("\n")
    end

    def allocation_section
      summary = Allocations::SummaryService.call(user: @user)
      lines = ["## Asset Allocation"]

      if summary.buckets.empty?
        lines << "No allocation buckets configured."
        return lines.join("\n")
      end

      lines << "| Bucket | Target % | Actual % | Drift % |"
      lines << "|--------|----------|----------|---------|"
      summary.buckets.each do |b|
        target = b.target_pct ? "#{b.target_pct}%" : "—"
        actual = b.actual_pct ? "#{b.actual_pct}%" : "—"
        drift  = b.drift_pct  ? "#{b.drift_pct > 0 ? '+' : ''}#{b.drift_pct}%" : "—"
        lines << "| #{b.name} | #{target} | #{actual} | #{drift} |"
      end
      lines.join("\n")
    end

    def watchlist_section
      tickers = @user.watchlist_tickers.ordered.map(&:ticker)
      lines = ["## Watchlist"]

      if tickers.empty?
        lines << "No watchlist tickers."
        return lines.join("\n")
      end

      fundamentals = StockFundamental.for_tickers(tickers)

      lines << "| Ticker | P/E | Fwd P/E | PEG | Net Margin% | ROE% |"
      lines << "|--------|-----|---------|-----|-------------|------|"
      tickers.each do |ticker|
        f = fundamentals[ticker]
        pe      = f&.pe      ? f.pe.round(1)      : "—"
        fwd_pe  = f&.fwd_pe  ? f.fwd_pe.round(1)  : "—"
        peg     = f&.peg     ? f.peg.round(2)     : "—"
        margin  = f&.net_margin ? "#{f.net_margin.round(1)}%" : "—"
        roe     = f&.roe     ? "#{f.roe.round(1)}%" : "—"
        lines << "| #{ticker} | #{pe} | #{fwd_pe} | #{peg} | #{margin} | #{roe} |"
      end
      lines.join("\n")
    end
  end
end
```

- [ ] **Step 4.4: Run tests to confirm they pass**

```bash
bin/rails test test/services/ai/portfolio_context_builder_test.rb
```

Expected: All tests pass.

- [ ] **Step 4.5: Commit**

```bash
git add app/services/ai/portfolio_context_builder.rb test/services/ai/portfolio_context_builder_test.rb
git commit -m "feat(ai): add PortfolioContextBuilder assembling all four data domains"
```

---

## Task 5: Routes + AI controller

**Files:**
- Modify: `config/routes.rb`
- Create: `app/controllers/ai_controller.rb`
- Create: `test/controllers/ai_controller_test.rb`

- [ ] **Step 5.1: Write the failing tests**

Create `test/controllers/ai_controller_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class AiControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @user.update!(password: "password", password_confirmation: "password")
    sign_in_as(@user)
  end

  # --- /ai/chat ---

  test "chat returns 401 redirect when not authenticated" do
    delete logout_path
    post ai_chat_path, params: { message: "hello" }, as: :json
    assert_response :redirect
  end

  test "chat returns no_api_key error when user has no Gemini key" do
    @user.update!(gemini_api_key: nil)
    post ai_chat_path, params: { message: "Analyze my portfolio" }, as: :json
    assert_response :unprocessable_entity
    json = JSON.parse(response.body)
    assert_equal "no_api_key", json["error"]
  end

  test "chat returns AI response on success" do
    @user.update!(gemini_api_key: "AIzaFakeKey12345678")
    Ai::PortfolioContextBuilder.stub(:new, ->(_opts) {
      ctx = Object.new
      ctx.define_singleton_method(:call) { "Portfolio context here" }
      ctx
    }) do
      Ai::GeminiService.stub(:new, ->(_opts) {
        svc = Object.new
        svc.define_singleton_method(:generate) { |_opts| "Great portfolio!" }
        svc
      }) do
        post ai_chat_path, params: { message: "Analyze my portfolio" }, as: :json
        assert_response :success
        json = JSON.parse(response.body)
        assert_equal "Great portfolio!", json["response"]
      end
    end
  end

  test "chat returns rate_limited error on Ai::RateLimitError" do
    @user.update!(gemini_api_key: "AIzaFakeKey12345678")
    Ai::PortfolioContextBuilder.stub(:new, ->(_opts) {
      ctx = Object.new; ctx.define_singleton_method(:call) { "" }; ctx
    }) do
      Ai::GeminiService.stub(:new, ->(_opts) {
        svc = Object.new
        svc.define_singleton_method(:generate) { |_opts| raise Ai::RateLimitError, "rate limited" }
        svc
      }) do
        post ai_chat_path, params: { message: "test" }, as: :json
        assert_response 429
        json = JSON.parse(response.body)
        assert_equal "rate_limited", json["error"]
      end
    end
  end

  test "chat returns invalid_key error on Ai::InvalidKeyError" do
    @user.update!(gemini_api_key: "AIzaBadKey")
    Ai::PortfolioContextBuilder.stub(:new, ->(_opts) {
      ctx = Object.new; ctx.define_singleton_method(:call) { "" }; ctx
    }) do
      Ai::GeminiService.stub(:new, ->(_opts) {
        svc = Object.new
        svc.define_singleton_method(:generate) { |_opts| raise Ai::InvalidKeyError, "bad key" }
        svc
      }) do
        post ai_chat_path, params: { message: "test" }, as: :json
        assert_response 401
        json = JSON.parse(response.body)
        assert_equal "invalid_key", json["error"]
      end
    end
  end

  # --- /ai/test_key ---

  test "test_key returns ok: true when key works" do
    Ai::GeminiService.stub(:new, ->(_opts) {
      svc = Object.new
      svc.define_singleton_method(:generate) { |_opts| "OK" }
      svc
    }) do
      post ai_test_key_path, params: { api_key: "AIzaGoodKey12345678" }, as: :json
      assert_response :success
      json = JSON.parse(response.body)
      assert_equal true, json["ok"]
    end
  end

  test "test_key returns invalid_key error when key is bad" do
    Ai::GeminiService.stub(:new, ->(_opts) {
      svc = Object.new
      svc.define_singleton_method(:generate) { |_opts| raise Ai::InvalidKeyError, "bad key" }
      svc
    }) do
      post ai_test_key_path, params: { api_key: "bad" }, as: :json
      assert_response 401
      json = JSON.parse(response.body)
      assert_equal "invalid_key", json["error"]
    end
  end

  private

  def sign_in_as(user)
    post login_path, params: { email: user.email, password: "password" }
    follow_redirect!
  end
end
```

- [ ] **Step 5.2: Run the tests to confirm they fail**

```bash
bin/rails test test/controllers/ai_controller_test.rb
```

Expected: Routing error — `No route matches [POST] "/ai/chat"`.

- [ ] **Step 5.3: Add routes**

In `config/routes.rb`, add before the final `end`:

```ruby
post "ai/chat",     to: "ai#chat",     as: :ai_chat
post "ai/test_key", to: "ai#test_key", as: :ai_test_key
```

- [ ] **Step 5.4: Create the AI controller**

Create `app/controllers/ai_controller.rb`:

```ruby
# frozen_string_literal: true

class AiController < ApplicationController
  SYSTEM_PROMPT = <<~PROMPT.freeze
    You are a portfolio analysis assistant for a complete investment tracker.
    You have access to the user's crypto futures trading positions, spot holdings,
    stock portfolio, asset allocation, and watchlist with fundamentals.
    Provide insights about trading performance, diversification, sector and asset exposure,
    risk, and watchlist valuations when asked.
    You are NOT a financial advisor — always remind users to do their own research.
    Never give specific buy/sell recommendations.
    Be concise and data-driven in your analysis.
  PROMPT

  def chat
    unless current_user.gemini_api_key_configured?
      return render json: {
        error: "no_api_key",
        message: "Please add your Gemini API key in Settings to use the AI assistant."
      }, status: :unprocessable_entity
    end

    message = params[:message].to_s.strip
    return render json: { error: "empty_message", message: "Message cannot be blank." }, status: :unprocessable_entity if message.blank?

    context = Ai::PortfolioContextBuilder.new(user: current_user).call
    prompt = "#{SYSTEM_PROMPT}Today's date: #{Date.today}.\n\n#{context}\n\nUser question: #{message}"

    response_text = Ai::GeminiService.new(api_key: current_user.gemini_api_key).generate(prompt: prompt)
    render json: { response: response_text }
  rescue Ai::RateLimitError
    render json: {
      error: "rate_limited",
      message: "You've hit your free tier limit. Try again in a moment."
    }, status: 429
  rescue Ai::InvalidKeyError
    render json: {
      error: "invalid_key",
      message: "Your API key appears to be invalid. Please check it in Settings."
    }, status: :unauthorized
  rescue Ai::ServiceError => e
    render json: {
      error: "service_error",
      message: "The AI service is temporarily unavailable."
    }, status: :unprocessable_entity
  end

  def test_key
    api_key = params[:api_key].to_s.strip
    return render json: { error: "no_api_key", message: "API key cannot be blank." }, status: :unprocessable_entity if api_key.blank?

    Ai::GeminiService.new(api_key: api_key).generate(prompt: "Say OK")
    render json: { ok: true }
  rescue Ai::RateLimitError
    render json: { error: "rate_limited", message: "Rate limited. Try again in a moment." }, status: 429
  rescue Ai::InvalidKeyError
    render json: { error: "invalid_key", message: "Your API key appears to be invalid." }, status: :unauthorized
  rescue Ai::ServiceError
    render json: { error: "service_error", message: "Could not reach the AI service." }, status: :unprocessable_entity
  end
end
```

- [ ] **Step 5.5: Add `test_saved_key` action to AiController**

This action lets the Settings page test the already-stored key without re-sending it to the frontend. Append to `app/controllers/ai_controller.rb` (before the final `end`):

```ruby
def test_saved_key
  unless current_user.gemini_api_key_configured?
    return render json: { error: "no_api_key", message: "No key configured." }, status: :unprocessable_entity
  end

  Ai::GeminiService.new(api_key: current_user.gemini_api_key).generate(prompt: "Say OK")
  render json: { ok: true }
rescue Ai::RateLimitError
  render json: { error: "rate_limited", message: "Rate limited. Try again in a moment." }, status: 429
rescue Ai::InvalidKeyError
  render json: { error: "invalid_key", message: "Your API key appears to be invalid." }, status: :unauthorized
rescue Ai::ServiceError
  render json: { error: "service_error", message: "Could not reach the AI service." }, status: :unprocessable_entity
end
```

Add to `config/routes.rb`:

```ruby
post "ai/test_saved_key", to: "ai#test_saved_key", as: :ai_test_saved_key
```

Add a test to `test/controllers/ai_controller_test.rb`:

```ruby
test "test_saved_key returns ok when stored key works" do
  @user.update!(gemini_api_key: "AIzaStoredKey12345678")
  Ai::GeminiService.stub(:new, ->(_opts) {
    svc = Object.new
    svc.define_singleton_method(:generate) { |_opts| "OK" }
    svc
  }) do
    post ai_test_saved_key_path, as: :json
    assert_response :success
    json = JSON.parse(response.body)
    assert_equal true, json["ok"]
  end
end

test "test_saved_key returns no_api_key when no key configured" do
  @user.update!(gemini_api_key: nil)
  post ai_test_saved_key_path, as: :json
  assert_response :unprocessable_entity
  json = JSON.parse(response.body)
  assert_equal "no_api_key", json["error"]
end
```

- [ ] **Step 5.6: Run the tests to confirm they pass**

```bash
bin/rails test test/controllers/ai_controller_test.rb
```

Expected: All tests pass.

- [ ] **Step 5.7: Commit**

```bash
git add config/routes.rb app/controllers/ai_controller.rb test/controllers/ai_controller_test.rb
git commit -m "feat(ai): add AiController with chat, test_key, and test_saved_key actions"
```

---

## Task 6: Settings controller additions

**Files:**
- Modify: `config/routes.rb`
- Modify: `app/controllers/settings_controller.rb`
- Modify: `test/controllers/settings_controller_test.rb`

- [ ] **Step 6.1: Write failing tests**

The settings controller test file doesn't exist yet. Create `test/controllers/settings_controller_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class SettingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @user.update!(password: "password", password_confirmation: "password")
    sign_in_as(@user)
  end

  test "show renders successfully" do
    get settings_path
    assert_response :success
  end

  test "update_ai_key saves the API key" do
    patch settings_ai_key_path, params: { api_key: "AIzaNewKey12345678" }
    assert_redirected_to settings_path
    @user.reload
    assert_equal "AIzaNewKey12345678", @user.gemini_api_key
  end

  test "remove_ai_key clears the API key" do
    @user.update!(gemini_api_key: "AIzaExistingKey1234")
    delete settings_ai_key_path
    assert_redirected_to settings_path
    @user.reload
    assert_nil @user.gemini_api_key
  end

  test "update_ai_key requires authentication" do
    delete logout_path
    patch settings_ai_key_path, params: { api_key: "AIzaNewKey12345678" }
    assert_response :redirect
  end

  private

  def sign_in_as(user)
    post login_path, params: { email: user.email, password: "password" }
    follow_redirect!
  end
end
```

- [ ] **Step 6.2: Run tests to confirm they fail**

```bash
bin/rails test test/controllers/settings_controller_test.rb
```

Expected: Routing error — `No route matches [PATCH] "/settings/ai_key"`.

- [ ] **Step 6.3: Add routes**

In `config/routes.rb`, replace the existing settings line:

```ruby
resource :settings, only: %i[show update], controller: "settings"
```

With:

```ruby
resource :settings, only: %i[show update], controller: "settings"
patch "settings/ai_key",  to: "settings#update_ai_key", as: :settings_ai_key
delete "settings/ai_key", to: "settings#remove_ai_key",  as: :remove_settings_ai_key
```

- [ ] **Step 6.4: Add actions to the settings controller**

In `app/controllers/settings_controller.rb`, add two new actions and update `settings_params`:

```ruby
def update_ai_key
  current_user.update!(gemini_api_key: params[:api_key].to_s.strip.presence)
  redirect_to settings_path, notice: "AI Assistant key saved."
end

def remove_ai_key
  current_user.update!(gemini_api_key: nil)
  redirect_to settings_path, notice: "AI Assistant key removed."
end
```

- [ ] **Step 6.5: Run the tests to confirm they pass**

```bash
bin/rails test test/controllers/settings_controller_test.rb
```

Expected: All tests pass.

- [ ] **Step 6.6: Run the full test suite to catch regressions**

```bash
bin/rails test
```

Expected: All tests pass.

- [ ] **Step 6.7: Commit**

```bash
git add config/routes.rb app/controllers/settings_controller.rb test/controllers/settings_controller_test.rb
git commit -m "feat(ai): add update_ai_key and remove_ai_key to SettingsController"
```

---

## Task 7: Settings view — AI Assistant section

**Files:**
- Modify: `app/views/settings/show.html.erb`

- [ ] **Step 7.1: Add the AI Assistant fieldset**

In `app/views/settings/show.html.erb`, before the closing `</div>` (just after the submit button for the sync form), add:

```erb
<hr class="my-8 border-slate-200">

<fieldset>
  <legend class="block text-sm font-medium text-slate-900">AI Assistant</legend>
  <p class="mb-4 text-sm text-slate-500">
    Connect your own Gemini API key to enable the AI portfolio assistant. No credit card needed —
    <a href="https://aistudio.google.com/app/apikey" target="_blank" rel="noopener noreferrer"
       class="text-indigo-600 underline hover:text-indigo-800">get a free key at Google AI Studio</a>.
  </p>

  <% if current_user.gemini_api_key_configured? %>
    <div class="flex items-center gap-4 rounded-lg border border-slate-200 bg-white p-4">
      <div class="flex-1">
        <p class="text-sm text-slate-700">
          <span class="font-medium">Current key:</span>
          <code class="ml-1 rounded bg-slate-100 px-1.5 py-0.5 text-xs font-mono text-slate-800"><%= current_user.gemini_api_key_masked %></code>
        </p>
      </div>
      <div class="flex items-center gap-2">
        <button type="button"
                id="test-key-btn"
                class="rounded-md border border-slate-300 bg-white px-3 py-1.5 text-sm font-medium text-slate-700 hover:bg-slate-50"
                onclick="testExistingKey()">
          Test connection
        </button>
        <%= button_to "Remove", remove_settings_ai_key_path, method: :delete,
              class: "rounded-md border border-red-200 bg-white px-3 py-1.5 text-sm font-medium text-red-600 hover:bg-red-50",
              data: { turbo_confirm: "Remove your Gemini API key?" } %>
      </div>
    </div>
    <p id="test-key-result" class="mt-2 hidden text-sm"></p>
  <% else %>
    <div class="space-y-3">
      <div class="flex gap-3">
        <input type="text"
               id="gemini-api-key-input"
               placeholder="AIzaSy..."
               class="flex-1 rounded-md border border-slate-300 bg-white px-3 py-2 text-sm focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500">
        <button type="button"
                id="test-key-btn"
                class="rounded-md border border-slate-300 bg-white px-3 py-1.5 text-sm font-medium text-slate-700 hover:bg-slate-50"
                onclick="testNewKey()">
          Test connection
        </button>
        <button type="button"
                class="rounded-md bg-slate-800 px-4 py-2 text-sm font-medium text-white hover:bg-slate-700"
                onclick="saveKey()">
          Save
        </button>
      </div>
      <p id="test-key-result" class="hidden text-sm"></p>
    </div>
  <% end %>
</fieldset>

<script>
  const csrfToken = () => document.querySelector("meta[name=csrf-token]").content;

  function showResult(message, success) {
    const el = document.getElementById("test-key-result");
    el.textContent = message;
    el.className = "mt-2 text-sm " + (success ? "text-emerald-600" : "text-red-600");
    el.classList.remove("hidden");
  }

  async function testExistingKey() {
    const btn = document.getElementById("test-key-btn");
    btn.disabled = true;
    btn.textContent = "Testing...";
    try {
      const res = await fetch("<%= ai_test_saved_key_path %>", {
        method: "POST",
        headers: { "Content-Type": "application/json", "X-CSRF-Token": csrfToken() }
      });
      const data = await res.json();
      showResult(data.ok ? "✓ Connected successfully" : (data.message || "Connection failed"), data.ok);
    } catch {
      showResult("Network error. Please try again.", false);
    } finally {
      btn.disabled = false;
      btn.textContent = "Test connection";
    }
  }

  async function testNewKey() {
    const key = document.getElementById("gemini-api-key-input")?.value?.trim();
    if (!key) return showResult("Enter an API key first.", false);
    const btn = document.getElementById("test-key-btn");
    btn.disabled = true;
    btn.textContent = "Testing...";
    try {
      const res = await fetch("<%= ai_test_key_path %>", {
        method: "POST",
        headers: { "Content-Type": "application/json", "X-CSRF-Token": csrfToken() },
        body: JSON.stringify({ api_key: key })
      });
      const data = await res.json();
      showResult(data.ok ? "✓ Connected successfully" : (data.message || "Connection failed"), data.ok);
    } catch {
      showResult("Network error. Please try again.", false);
    } finally {
      btn.disabled = false;
      btn.textContent = "Test connection";
    }
  }

  function saveKey() {
    const key = document.getElementById("gemini-api-key-input")?.value?.trim();
    if (!key) return showResult("Enter an API key first.", false);
    const form = document.createElement("form");
    form.method = "post";
    form.action = "<%= settings_ai_key_path %>";
    const csrfInput = document.createElement("input");
    csrfInput.type = "hidden";
    csrfInput.name = "authenticity_token";
    csrfInput.value = csrfToken();
    const methodInput = document.createElement("input");
    methodInput.type = "hidden";
    methodInput.name = "_method";
    methodInput.value = "patch";
    const keyInput = document.createElement("input");
    keyInput.type = "hidden";
    keyInput.name = "api_key";
    keyInput.value = key;
    form.appendChild(csrfInput);
    form.appendChild(methodInput);
    form.appendChild(keyInput);
    document.body.appendChild(form);
    form.submit();
  }
</script>
```

The "Test connection" button for the saved-key state calls `ai_test_saved_key_path` (added in Task 5 Step 5.5) — no raw key is sent back to the browser.

- [ ] **Step 7.2: Verify settings tests still pass**

```bash
bin/rails test test/controllers/settings_controller_test.rb
```

Expected: All pass.

- [ ] **Step 7.3: Commit**

```bash
git add app/views/settings/show.html.erb config/routes.rb app/controllers/ai_controller.rb
git commit -m "feat(ai): add AI Assistant section to Settings page"
```

---

## Task 8: Stimulus AI chat controller

**Files:**
- Create: `app/javascript/controllers/ai_chat_controller.js`

The controller is auto-loaded by `pin_all_from "app/javascript/controllers"` in `config/importmap.rb` — no importmap change needed.

- [ ] **Step 8.1: Create the Stimulus controller**

Create `app/javascript/controllers/ai_chat_controller.js`:

```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "panel", "trigger", "messageList", "input", "sendBtn",
    "noKeyState", "chatState"
  ]
  static values = { hasKey: Boolean, chatUrl: String }

  connect() {
    this._onKeydown = (e) => { if (e.key === "Escape") this.close() }
    document.addEventListener("keydown", this._onKeydown)
    this._applyInitialState()
  }

  disconnect() {
    document.removeEventListener("keydown", this._onKeydown)
  }

  toggle() {
    this.panelTarget.classList.contains("hidden") ? this.open() : this.close()
  }

  open() {
    this.panelTarget.classList.remove("hidden")
    this.panelTarget.classList.add("flex")
    if (this.hasKeyValue && this.hasInputTarget) {
      this.inputTarget.focus()
    }
  }

  close() {
    this.panelTarget.classList.add("hidden")
    this.panelTarget.classList.remove("flex")
  }

  quickAction(event) {
    const prompt = event.currentTarget.dataset.prompt
    if (this.hasInputTarget) {
      this.inputTarget.value = prompt
    }
    this.send()
  }

  async send() {
    const message = this.hasInputTarget ? this.inputTarget.value.trim() : ""
    if (!message) return

    this._appendUserMessage(message)
    if (this.hasInputTarget) this.inputTarget.value = ""
    this._setCooldown()

    const loadingId = this._appendLoading()

    try {
      const response = await fetch(this.chatUrlValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": document.querySelector("meta[name=csrf-token]").content
        },
        body: JSON.stringify({ message })
      })

      const data = await response.json()
      this._removeLoading(loadingId)

      if (data.error) {
        this._appendError(data.error, data.message)
      } else {
        this._appendAiMessage(data.response)
      }
    } catch (_e) {
      this._removeLoading(loadingId)
      this._appendAiMessage("Network error. Please try again.")
    }
  }

  // private

  _applyInitialState() {
    if (this.hasKeyValue) {
      if (this.hasNoKeyStateTarget) this.noKeyStateTarget.classList.add("hidden")
      if (this.hasChatStateTarget) this.chatStateTarget.classList.remove("hidden")
    } else {
      if (this.hasNoKeyStateTarget) this.noKeyStateTarget.classList.remove("hidden")
      if (this.hasChatStateTarget) this.chatStateTarget.classList.add("hidden")
    }
  }

  _appendUserMessage(text) {
    const row = document.createElement("div")
    row.className = "flex justify-end mb-3"
    const bubble = document.createElement("div")
    bubble.className = "max-w-[75%] rounded-2xl rounded-tr-sm bg-indigo-600 px-3 py-2 text-sm text-white"
    bubble.textContent = text
    row.appendChild(bubble)
    this.messageListTarget.appendChild(row)
    this._scrollToBottom()
  }

  _appendAiMessage(text) {
    const row = document.createElement("div")
    row.className = "flex justify-start mb-3"
    const bubble = document.createElement("div")
    bubble.className = "max-w-[75%] rounded-2xl rounded-tl-sm bg-slate-100 px-3 py-2 text-sm text-slate-800 whitespace-pre-wrap"
    bubble.textContent = text
    row.appendChild(bubble)
    this.messageListTarget.appendChild(row)
    this._scrollToBottom()
  }

  _appendError(errorCode, message) {
    const row = document.createElement("div")
    row.className = "mb-3"
    const bubble = document.createElement("div")

    if (errorCode === "invalid_key") {
      bubble.className = "rounded-lg bg-red-50 px-3 py-2 text-sm text-red-700"
      bubble.innerHTML = `${message} <a href="/settings" class="underline font-medium">Update in Settings</a>`
    } else if (errorCode === "rate_limited") {
      bubble.className = "rounded-lg bg-amber-50 px-3 py-2 text-sm text-amber-700"
      bubble.textContent = message
    } else {
      bubble.className = "rounded-lg bg-red-50 px-3 py-2 text-sm text-red-700"
      bubble.textContent = message
    }

    row.appendChild(bubble)
    this.messageListTarget.appendChild(row)
    this._scrollToBottom()
  }

  _appendLoading() {
    const id = `ai-loading-${Date.now()}`
    const row = document.createElement("div")
    row.id = id
    row.className = "flex justify-start mb-3"
    row.innerHTML = `<div class="rounded-2xl rounded-tl-sm bg-slate-100 px-3 py-2 text-sm text-slate-400">Thinking…</div>`
    this.messageListTarget.appendChild(row)
    this._scrollToBottom()
    return id
  }

  _removeLoading(id) {
    document.getElementById(id)?.remove()
  }

  _setCooldown() {
    if (!this.hasSendBtnTarget) return
    this.sendBtnTarget.disabled = true
    setTimeout(() => { this.sendBtnTarget.disabled = false }, 3000)
  }

  _scrollToBottom() {
    this.messageListTarget.scrollTop = this.messageListTarget.scrollHeight
  }
}
```

- [ ] **Step 8.2: Commit**

```bash
git add app/javascript/controllers/ai_chat_controller.js
git commit -m "feat(ai): add AiChat Stimulus controller with chat, quick-actions, and error handling"
```

---

## Task 9: Application layout — floating panel

**Files:**
- Modify: `app/views/layouts/application.html.erb`

- [ ] **Step 9.1: Add the floating button and panel to the authenticated layout**

In `app/views/layouts/application.html.erb`, find the line:

```erb
      </div><%# end data-controller="nav" %>
```

Just **before** that closing `</div>`, add:

```erb
    <%# ── AI Assistant floating panel ─────────────────────────────────────── %>
    <div data-controller="ai-chat"
         data-ai-chat-has-key-value="<%= current_user.gemini_api_key_configured? %>"
         data-ai-chat-chat-url-value="<%= ai_chat_path %>">

      <%# Floating trigger button %>
      <button type="button"
              data-action="ai-chat#toggle"
              data-ai-chat-target="trigger"
              aria-label="Open AI Assistant"
              class="fixed bottom-6 right-6 z-50 flex h-12 w-12 items-center justify-center rounded-full bg-indigo-600 text-white shadow-lg transition-transform hover:scale-105 hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:ring-offset-2">
        <svg class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" aria-hidden="true">
          <path stroke-linecap="round" stroke-linejoin="round" d="M9.813 15.904 9 18.75l-.813-2.846a4.5 4.5 0 0 0-3.09-3.09L2.25 12l2.846-.813a4.5 4.5 0 0 0 3.09-3.09L9 5.25l.813 2.846a4.5 4.5 0 0 0 3.09 3.09L15.75 12l-2.846.813a4.5 4.5 0 0 0-3.09 3.09Z" />
          <path stroke-linecap="round" stroke-linejoin="round" d="M18.259 8.715 18 9.75l-.259-1.035a3.375 3.375 0 0 0-2.455-2.456L14.25 6l1.036-.259a3.375 3.375 0 0 0 2.455-2.456L18 2.25l.259 1.035a3.375 3.375 0 0 0 2.456 2.456L21.75 6l-1.035.259a3.375 3.375 0 0 0-2.456 2.456Z" />
        </svg>
      </button>

      <%# Slide-in panel %>
      <div data-ai-chat-target="panel"
           class="fixed inset-y-0 right-0 z-50 hidden w-full flex-col bg-white shadow-2xl sm:w-96 border-l border-slate-200">

        <%# Panel header %>
        <div class="flex items-center justify-between border-b border-slate-200 px-4 py-3">
          <div class="flex items-center gap-2">
            <svg class="h-4 w-4 text-indigo-600" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" aria-hidden="true">
              <path stroke-linecap="round" stroke-linejoin="round" d="M9.813 15.904 9 18.75l-.813-2.846a4.5 4.5 0 0 0-3.09-3.09L2.25 12l2.846-.813a4.5 4.5 0 0 0 3.09-3.09L9 5.25l.813 2.846a4.5 4.5 0 0 0 3.09 3.09L15.75 12l-2.846.813a4.5 4.5 0 0 0-3.09 3.09Z" />
            </svg>
            <span class="text-sm font-semibold text-slate-900">AI Assistant</span>
          </div>
          <button type="button"
                  data-action="ai-chat#close"
                  aria-label="Close AI Assistant"
                  class="rounded-md p-1.5 text-slate-400 hover:bg-slate-100 hover:text-slate-600">
            <svg class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" aria-hidden="true">
              <path stroke-linecap="round" stroke-linejoin="round" d="M6 18 18 6M6 6l12 12" />
            </svg>
          </button>
        </div>

        <%# No-key state %>
        <div data-ai-chat-target="noKeyState" class="flex flex-1 flex-col items-center justify-center gap-4 p-6 text-center">
          <div class="flex h-14 w-14 items-center justify-center rounded-full bg-indigo-50">
            <svg class="h-7 w-7 text-indigo-500" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" aria-hidden="true">
              <path stroke-linecap="round" stroke-linejoin="round" d="M15.75 5.25a3 3 0 0 1 3 3m3 0a6 6 0 0 1-7.029 5.912c-.563-.097-1.159.026-1.563.43L10.5 17.25H8.25v2.25H6v2.25H2.25v-2.818c0-.597.237-1.17.659-1.591l6.499-6.499c.404-.404.527-1 .43-1.563A6 6 0 0 1 21.75 8.25Z" />
            </svg>
          </div>
          <div>
            <p class="font-medium text-slate-900">AI Assistant not configured</p>
            <p class="mt-1 text-sm text-slate-500">Add your free Gemini API key to unlock AI portfolio analysis.</p>
          </div>
          <%= link_to "Set up in Settings", settings_path,
                class: "rounded-md bg-indigo-600 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-700" %>
        </div>

        <%# Chat state %>
        <div data-ai-chat-target="chatState" class="hidden flex-1 flex-col overflow-hidden">

          <%# Message list %>
          <div data-ai-chat-target="messageList"
               class="flex-1 overflow-y-auto px-4 py-4 space-y-1">
            <div class="flex justify-start mb-3">
              <div class="max-w-[80%] rounded-2xl rounded-tl-sm bg-slate-100 px-3 py-2 text-sm text-slate-700">
                Hello! I can help you analyze your portfolio. Ask me anything or use a quick action below.
              </div>
            </div>
          </div>

          <%# Quick actions %>
          <div class="border-t border-slate-100 px-3 py-3">
            <p class="mb-2 text-xs font-medium uppercase tracking-wide text-slate-400">Quick actions</p>
            <div class="grid grid-cols-2 gap-1.5">
              <% [
                ["Analyze my full portfolio",               "Analyze my full portfolio across all asset classes: futures, spot, stocks, and allocation."],
                ["How diversified am I?",                   "How diversified am I across asset classes, sectors, and instruments? What concentration risks do I have?"],
                ["Summarize my asset allocation",           "Summarize my current asset allocation and compare it to my targets. Where are the biggest drifts?"],
                ["Review futures performance",              "Review my crypto futures trading performance. What are my win rate, average win/loss, and biggest strengths or weaknesses?"],
                ["Where am I losing in futures?",           "Where am I losing the most in my crypto futures positions? Which symbols or setups are dragging my performance?"],
                ["Win rate trend",                          "Analyze my futures win rate and consistency. Am I improving or getting worse over time?"],
                ["Analyze my spot holdings",                "Analyze my spot crypto holdings. How is my exposure distributed and what is my cost basis situation?"],
                ["Review my stock portfolio",               "Review my stock portfolio. How are my positions performing and where is my cost basis vs breakeven?"],
                ["Evaluate watchlist valuations",           "Evaluate the valuation of my watchlist stocks using the fundamentals data. Which ones look attractive or expensive?"],
              ].each do |label, prompt| %>
                <button type="button"
                        data-action="ai-chat#quickAction"
                        data-prompt="<%= prompt %>"
                        class="rounded-lg border border-slate-200 bg-white px-2 py-1.5 text-left text-xs text-slate-700 hover:border-indigo-300 hover:bg-indigo-50 hover:text-indigo-700 transition-colors">
                  <%= label %>
                </button>
              <% end %>
            </div>
          </div>

          <%# Input row %>
          <div class="border-t border-slate-200 px-3 py-3">
            <div class="flex gap-2">
              <textarea data-ai-chat-target="input"
                        placeholder="Ask about your portfolio…"
                        rows="2"
                        class="flex-1 resize-none rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500"
                        data-action="keydown.ctrl+enter->ai-chat#send keydown.meta+enter->ai-chat#send"></textarea>
              <button type="button"
                      data-action="ai-chat#send"
                      data-ai-chat-target="sendBtn"
                      class="self-end rounded-lg bg-indigo-600 px-3 py-2 text-sm font-medium text-white hover:bg-indigo-700 disabled:cursor-not-allowed disabled:opacity-50">
                Send
              </button>
            </div>
            <p class="mt-1.5 text-xs text-slate-400">Powered by Gemini 2.5 Flash · Your key, your data</p>
          </div>
        </div>
      </div>
    </div>
```

- [ ] **Step 9.2: Run the full test suite**

```bash
bin/rails test
```

Expected: All tests pass.

- [ ] **Step 9.3: Commit**

```bash
git add app/views/layouts/application.html.erb
git commit -m "feat(ai): add floating AI chat panel to authenticated layout"
```

---

## Task 10: Smoke test end-to-end

- [ ] **Step 10.1: Start the development server**

```bash
./bin/dev
```

- [ ] **Step 10.2: Verify the floating button appears on all pages**

Visit `http://localhost:5000`. The indigo sparkle button should appear bottom-right on the dashboard, trades, spot, stocks, and allocation pages.

- [ ] **Step 10.3: Verify the no-key state**

Click the button while no Gemini key is configured. The panel should open showing "AI Assistant not configured" with a link to Settings.

- [ ] **Step 10.4: Add an API key in Settings**

Go to Settings, enter a Gemini API key in the AI Assistant section, click "Test connection" (should show green checkmark), then "Save".

- [ ] **Step 10.5: Verify the chat UI appears after saving a key**

Click the floating button — the panel should now show the chat UI with quick-action buttons.

- [ ] **Step 10.6: Send a quick action**

Click "Analyze my full portfolio". The Thinking… indicator should appear, then the AI response.

- [ ] **Step 10.7: Run the full test suite one final time**

```bash
bin/rails test
```

Expected: All tests pass.

- [ ] **Step 10.8: Final commit**

```bash
git add -A
git commit -m "feat(ai): complete AI assistant — floating panel, BYOK Gemini, all data domains"
```
