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

    def gemini_response(body)
      # GeminiService wraps the text in candidates[]/content/parts[]/text
      wrapped = JSON.generate({
        "candidates" => [{
          "content" => { "parts" => [{ "text" => body }] }
        }]
      })
      res = Object.new
      res.define_singleton_method(:code) { "200" }
      res.define_singleton_method(:body) { wrapped }
      res
    end

    def gemini_error_response(code)
      res = Object.new
      res.define_singleton_method(:code) { code.to_s }
      res.define_singleton_method(:body) { "{}" }
      res
    end

    def stub_http(response)
      fake = Object.new
      fake.define_singleton_method(:use_ssl=)      { |_| }
      fake.define_singleton_method(:open_timeout=) { |_| }
      fake.define_singleton_method(:read_timeout=) { |_| }
      fake.define_singleton_method(:request)       { |_req| response }
      Net::HTTP.stub(:new, fake) { yield }
    end

    setup do
      @user = users(:two)
      @user.update!(gemini_api_key: "AIzaTestKey123")
    end

    test "skips user without Gemini key" do
      @user.update!(gemini_api_key: nil)
      call_count = 0
      Net::HTTP.stub(:new, ->(*) { call_count += 1; raise "should not be called" }) do
        Stocks::SyncStockAnalysisJob.new.perform(@user.id, ["AAPL"])
      end
      assert_equal 0, call_count
    end

    test "upserts analysis for each ticker" do
      StockFundamental.stub(:for_tickers, { "AAPL" => stock_fundamentals(:aapl) }) do
        stub_http(gemini_response(JSON.generate(GEMINI_JSON))) do
          Stocks::SyncStockAnalysisJob.new.perform(@user.id, ["AAPL"])
        end
      end

      analysis = StockAnalysis.find_by!(user: @user, ticker: "AAPL")
      assert_equal "buy",                                   analysis.rating
      assert_equal "Strong moat with durable cash flows.",  analysis.executive_summary
      assert_equal "Good — low leverage, dominant brand.",  analysis.risk_reward_rating
      assert_equal "Apple ecosystem creates switching costs.", analysis.thesis_breakdown
      assert_equal "None",                                  analysis.red_flags
      assert_not_nil analysis.analyzed_at
    end

    test "skips ticker on Gemini rate limit error and continues" do
      call_count = 0
      fundamentals = {
        "AAPL" => stock_fundamentals(:aapl),
        "MSFT" => stock_fundamentals(:aapl) # reuse fixture data, different ticker
      }

      error_res   = gemini_error_response(429)
      success_res = gemini_response(JSON.generate(GEMINI_JSON))

      StockFundamental.stub(:for_tickers, fundamentals) do
        fake = Object.new
        fake.define_singleton_method(:use_ssl=)      { |_| }
        fake.define_singleton_method(:open_timeout=) { |_| }
        fake.define_singleton_method(:read_timeout=) { |_| }
        fake.define_singleton_method(:request) do |_req|
          call_count += 1
          call_count == 1 ? error_res : success_res
        end
        Net::HTTP.stub(:new, fake) do
          Stocks::SyncStockAnalysisJob.new.perform(@user.id, ["AAPL", "MSFT"])
        end
      end

      assert_nil StockAnalysis.find_by(user: @user, ticker: "AAPL")
      assert_not_nil StockAnalysis.find_by(user: @user, ticker: "MSFT")
    end

    test "skips ticker when Gemini response text is not valid JSON" do
      StockFundamental.stub(:for_tickers, { "AAPL" => stock_fundamentals(:aapl) }) do
        stub_http(gemini_response("not json at all")) do
          assert_nothing_raised { Stocks::SyncStockAnalysisJob.new.perform(@user.id, ["AAPL"]) }
        end
      end

      assert_nil StockAnalysis.find_by(user: @user, ticker: "AAPL")
    end
  end
end
