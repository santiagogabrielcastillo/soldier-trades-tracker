# frozen_string_literal: true

require "test_helper"

module Stocks
  class SyncStockAnalysisJobTest < ActiveSupport::TestCase
    GEMINI_JSON = {
      "rating"             => "buy",
      "executive_summary"  => "Strong moat with durable cash flows.",
      "risk_reward_rating" => "Good — low leverage, dominant brand.",
      "thesis_breakdown"   => "Apple ecosystem creates switching costs.",
      "red_flags"          => "None"
    }.freeze

    CLAUDE_JSON = {
      "verdict"            => "accumulate",
      "verdict_label"      => "Accumulate — wide moat at reasonable price",
      "company_name"       => "Apple Inc.",
      "analyzed_at"        => "2026-04-15",
      "metrics"            => { "price" => { "value" => "$175", "subtitle" => "-10% from 52w high" } },
      "moat"               => { "overall" => "wide", "scores" => {}, "primary_threat" => "AI hardware risk" },
      "revenue_trend"      => [ { "year" => "FY25", "revenue" => 395.0, "fcf" => 103.0 } ],
      "revenue_unit"       => "B",
      "tags"               => [ { "label" => "Net cash", "color" => "green" } ],
      "asset_classification" => "light",
      "turnaround_mode"    => false,
      "turnaround_bucket"  => nil,
      "executive_summary"  => "Apple has a durable ecosystem moat.",
      "thesis_breakdown"   => "Switching costs remain high.",
      "risk_reward_rating" => "Excellent",
      "red_flags"          => "1. China concentration.",
      "what_to_watch"      => "Q2 FY26 earnings.",
      "sources"            => [ "https://example.com" ]
    }.freeze

    # ── HTTP helpers ──────────────────────────────────────────────────────────

    def fake_response(code:, body:)
      res = Object.new
      res.define_singleton_method(:code) { code.to_s }
      res.define_singleton_method(:body) { body }
      res
    end

    def gemini_response(json_text)
      wrapped = JSON.generate({
        "candidates" => [ { "content" => { "parts" => [ { "text" => json_text } ] } } ]
      })
      fake_response(code: "200", body: wrapped)
    end

    def claude_response(json_text)
      wrapped = JSON.generate({ "content" => [ { "type" => "text", "text" => json_text } ] })
      fake_response(code: "200", body: wrapped)
    end

    def stub_http(response)
      fake = Object.new
      fake.define_singleton_method(:use_ssl=)      { |_| }
      fake.define_singleton_method(:open_timeout=) { |_| }
      fake.define_singleton_method(:read_timeout=) { |_| }
      fake.define_singleton_method(:request)       { |_req| response }
      Net::HTTP.stub(:new, fake) { yield }
    end

    # ── provider helpers ──────────────────────────────────────────────────────

    def with_anthropic_key(key, &block)
      Rails.application.credentials.stub(:dig, ->(*args) {
        args == [ :anthropic, :api_key ] ? key : nil
      }, &block)
    end

    def with_no_anthropic_key(&block)
      Rails.application.credentials.stub(:dig, ->(*_args) { nil }, &block)
    end

    # ── setup ─────────────────────────────────────────────────────────────────

    setup do
      @user = users(:two)
      @user.update!(gemini_api_key: "AIzaTestKey123")
    end

    # ── guard: skips when no provider configured ───────────────────────────────

    test "skips user without any AI key configured" do
      @user.update!(gemini_api_key: nil)
      call_count = 0
      with_no_anthropic_key do
        Net::HTTP.stub(:new, ->(*) { call_count += 1; raise "should not be called" }) do
          Stocks::SyncStockAnalysisJob.new.perform(@user.id, [ "AAPL" ])
        end
      end
      assert_equal 0, call_count
    end

    # ── Gemini path ────────────────────────────────────────────────────────────

    test "upserts analysis via Gemini when no anthropic key" do
      StockFundamental.stub(:for_tickers, { "AAPL" => stock_fundamentals(:aapl) }) do
        with_no_anthropic_key do
          stub_http(gemini_response(JSON.generate(GEMINI_JSON))) do
            Stocks::SyncStockAnalysisJob.new.perform(@user.id, [ "AAPL" ])
          end
        end
      end

      analysis = StockAnalysis.find_by!(user: @user, ticker: "AAPL")
      assert_equal "buy",     analysis.rating
      assert_equal "gemini",  analysis.provider
      assert_nil              analysis.structured_data
    end

    test "skips ticker on Gemini rate limit and continues to next" do
      fundamentals = { "AAPL" => stock_fundamentals(:aapl), "MSFT" => stock_fundamentals(:aapl) }
      call_count = 0
      error_res   = fake_response(code: "429", body: "{}")
      success_res = gemini_response(JSON.generate(GEMINI_JSON))

      StockFundamental.stub(:for_tickers, fundamentals) do
        with_no_anthropic_key do
          fake = Object.new
          fake.define_singleton_method(:use_ssl=)      { |_| }
          fake.define_singleton_method(:open_timeout=) { |_| }
          fake.define_singleton_method(:read_timeout=) { |_| }
          fake.define_singleton_method(:request) do |_req|
            call_count += 1
            call_count == 1 ? error_res : success_res
          end
          Net::HTTP.stub(:new, fake) do
            Stocks::SyncStockAnalysisJob.new.perform(@user.id, [ "AAPL", "MSFT" ])
          end
        end
      end

      assert_nil      StockAnalysis.find_by(user: @user, ticker: "AAPL")
      assert_not_nil  StockAnalysis.find_by(user: @user, ticker: "MSFT")
    end

    test "skips ticker when Gemini response text is not valid JSON" do
      StockFundamental.stub(:for_tickers, { "AAPL" => stock_fundamentals(:aapl) }) do
        with_no_anthropic_key do
          stub_http(gemini_response("not json at all")) do
            assert_nothing_raised { Stocks::SyncStockAnalysisJob.new.perform(@user.id, [ "AAPL" ]) }
          end
        end
      end
      assert_nil StockAnalysis.find_by(user: @user, ticker: "AAPL")
    end

    # ── Claude path ────────────────────────────────────────────────────────────

    test "upserts analysis via Claude when anthropic key configured" do
      @user.update!(gemini_api_key: nil)
      StockFundamental.stub(:for_tickers, { "AAPL" => stock_fundamentals(:aapl) }) do
        with_anthropic_key("sk-ant-test") do
          stub_http(claude_response(JSON.generate(CLAUDE_JSON))) do
            Stocks::SyncStockAnalysisJob.new.perform(@user.id, [ "AAPL" ])
          end
        end
      end

      analysis = StockAnalysis.find_by!(user: @user, ticker: "AAPL")
      assert_equal "accumulate",                                 analysis.rating
      assert_equal "claude",                                     analysis.provider
      assert_equal "Apple has a durable ecosystem moat.",        analysis.executive_summary
      assert_equal "Excellent",                                  analysis.risk_reward_rating
      assert_not_nil                                             analysis.structured_data
      assert_equal "Apple Inc.",                                 analysis.structured_data["company_name"]
    end

    test "stores full structured_data JSON for Claude analysis" do
      @user.update!(gemini_api_key: nil)
      StockFundamental.stub(:for_tickers, { "AAPL" => stock_fundamentals(:aapl) }) do
        with_anthropic_key("sk-ant-test") do
          stub_http(claude_response(JSON.generate(CLAUDE_JSON))) do
            Stocks::SyncStockAnalysisJob.new.perform(@user.id, [ "AAPL" ])
          end
        end
      end

      analysis = StockAnalysis.find_by!(user: @user, ticker: "AAPL")
      sd = analysis.structured_data
      assert_equal "wide",                sd.dig("moat", "overall")
      assert_equal "B",                   sd["revenue_unit"]
      assert_equal 1,                     sd["revenue_trend"].length
      assert_equal "Net cash",            sd.dig("tags", 0, "label")
    end

    test "strips markdown fences from Claude response" do
      fenced = "```json\n#{JSON.generate(CLAUDE_JSON)}\n```"
      @user.update!(gemini_api_key: nil)
      StockFundamental.stub(:for_tickers, { "AAPL" => stock_fundamentals(:aapl) }) do
        with_anthropic_key("sk-ant-test") do
          stub_http(claude_response(fenced)) do
            assert_nothing_raised { Stocks::SyncStockAnalysisJob.new.perform(@user.id, [ "AAPL" ]) }
          end
        end
      end
      assert_not_nil StockAnalysis.find_by(user: @user, ticker: "AAPL")
    end

    test "skips ticker on Claude AI error and continues" do
      fundamentals = { "AAPL" => stock_fundamentals(:aapl), "MSFT" => stock_fundamentals(:aapl) }
      call_count = 0
      error_res   = fake_response(code: "429", body: "{}")
      success_res = claude_response(JSON.generate(CLAUDE_JSON))

      StockFundamental.stub(:for_tickers, fundamentals) do
        with_anthropic_key("sk-ant-test") do
          fake = Object.new
          fake.define_singleton_method(:use_ssl=)      { |_| }
          fake.define_singleton_method(:open_timeout=) { |_| }
          fake.define_singleton_method(:read_timeout=) { |_| }
          fake.define_singleton_method(:request) do |_req|
            call_count += 1
            call_count == 1 ? error_res : success_res
          end
          Net::HTTP.stub(:new, fake) do
            Stocks::SyncStockAnalysisJob.new.perform(@user.id, [ "AAPL", "MSFT" ])
          end
        end
      end

      assert_nil     StockAnalysis.find_by(user: @user, ticker: "AAPL")
      assert_not_nil StockAnalysis.find_by(user: @user, ticker: "MSFT")
    end

    # ── normalize_rating ──────────────────────────────────────────────────────

    test "normalize_rating accepts all valid verdicts" do
      job = Stocks::SyncStockAnalysisJob.new
      %w[buy accumulate watch hold sell].each do |verdict|
        assert_equal verdict, job.send(:normalize_rating, verdict)
      end
    end

    test "normalize_rating is case-insensitive" do
      job = Stocks::SyncStockAnalysisJob.new
      assert_equal "buy", job.send(:normalize_rating, "BUY")
      assert_equal "buy", job.send(:normalize_rating, "Buy")
    end

    test "normalize_rating falls back to watch for unknown value" do
      job = Stocks::SyncStockAnalysisJob.new
      assert_equal "watch", job.send(:normalize_rating, "strong_buy")
      assert_equal "watch", job.send(:normalize_rating, nil)
      assert_equal "watch", job.send(:normalize_rating, "")
    end
  end
end
