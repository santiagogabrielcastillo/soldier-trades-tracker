# frozen_string_literal: true

require "test_helper"

module Exchanges
  class BinanceClientTest < ActiveSupport::TestCase
    setup do
      @client = BinanceClient.new(api_key: "test_key", api_secret: "test_secret")
    end

    test "signed_get raises ApiError for 429" do
      stub_http_response(code: "429", body: '{"msg":"rate limit"}', headers: { "Retry-After" => "60" }) do
        err = assert_raises(ApiError) { @client.signed_get("/fapi/v2/positionRisk", {}) }
        assert_match(/429/, err.message)
        assert_equal "429", err.response_code
        assert_equal 60, err.retry_after
      end
    end

    test "signed_get raises ApiError for 5xx" do
      stub_http_response(code: "502", body: "Bad Gateway") do
        err = assert_raises(ApiError) { @client.signed_get("/fapi/v2/positionRisk", {}) }
        assert_match(/502/, err.message)
        assert_equal "502", err.response_code
      end
    end

    test "signed_get raises ApiError for 200 with empty body" do
      stub_http_response(code: "200", body: "") do
        err = assert_raises(ApiError) { @client.signed_get("/fapi/v2/positionRisk", {}) }
        assert_match(/empty body/, err.message)
      end
    end

    test "signed_get raises ApiError on timeout" do
      stub_http_timeout(Net::ReadTimeout) do
        err = assert_raises(ApiError) { @client.signed_get("/fapi/v2/positionRisk", {}) }
        assert_match(/timeout/, err.message)
      end
    end

    test "fetch_my_trades returns empty when no symbols discovered" do
      @client.stub(:signed_get, ->(path, _params) {
        return [] if path == BinanceClient::POSITION_RISK_PATH
        return [] if path == BinanceClient::INCOME_PATH
        []
      }) do
        result = @client.fetch_my_trades(since: 1.day.ago)
        assert_equal [], result
      end
    end

    test "fetch_my_trades raises ApiError when Binance returns 200 with error body" do
      @client.stub(:signed_get, { "code" => -2015, "msg" => "Invalid API key" }) do
        err = assert_raises(ApiError) { @client.fetch_my_trades(since: 1.day.ago) }
        assert_match(/Invalid API key/, err.message)
        assert_match(/-2015/, err.message)
      end
    end

    test "fetch_my_trades discovers symbols from positionRisk and fetches userTrades" do
      time_ms = (Time.now.to_i - 3600) * 1000
      raw_trade = {
        "id" => "binance_trade_1",
        "symbol" => "BTCUSDT",
        "side" => "BUY",
        "price" => "50000",
        "qty" => "0.01",
        "commission" => "-0.05",
        "time" => time_ms,
        "positionSide" => "LONG"
      }
      call_count = 0
      stub_signed_get = lambda do |path, params|
        call_count += 1
        if path == BinanceClient::POSITION_RISK_PATH
          [ { "symbol" => "BTCUSDT", "positionAmt" => "0.1" } ]
        elsif path == BinanceClient::USER_TRADES_PATH && params["symbol"] == "BTCUSDT"
          [ raw_trade ]
        else
          []
        end
      end
      @client.stub(:signed_get, stub_signed_get) do
        result = @client.fetch_my_trades(since: 1.day.ago)
        assert_equal 1, result.size
        assert_equal "binance_trade_1", result[0][:exchange_reference_id]
        assert_equal "BTC-USDT", result[0][:symbol]
        assert_equal "buy", result[0][:side]
        assert_equal BigDecimal("50000"), result[0][:price]
        assert_equal BigDecimal("0.01"), result[0][:quantity]
        assert_equal BigDecimal("0.05"), result[0][:fee_from_exchange]
      end
    end

    test "fetch_my_trades fetches USDC symbol when USDC is in whitelist" do
      time_ms = (Time.now.to_i - 3600) * 1000
      raw_usdc_trade = {
        "id" => "usdc_trade_1",
        "symbol" => "BTCUSDC",
        "side" => "BUY",
        "price" => "50000",
        "qty" => "0.01",
        "commission" => "-0.05",
        "time" => time_ms,
        "positionSide" => "LONG"
      }
      stub = lambda do |path, params|
        if path == BinanceClient::INCOME_PATH
          [ { "symbol" => "BTCUSDC", "incomeType" => "REALIZED_PNL" } ]
        elsif path == BinanceClient::POSITION_RISK_PATH
          []
        elsif path == BinanceClient::USER_TRADES_PATH && params["symbol"] == "BTCUSDC"
          [ raw_usdc_trade ]
        else
          []
        end
      end
      @client.stub(:signed_get, stub) do
        result = @client.fetch_my_trades(since: 1.day.ago)
        assert_equal 1, result.size
        assert_equal "BTC-USDC", result[0][:symbol]
      end
    end

    test "fetch_my_trades skips userTrades fetch for symbols not in whitelist" do
      client = BinanceClient.new(api_key: "k", api_secret: "s", allowed_quote_currencies: [ "USDT" ])
      fetch_calls = []
      stub = lambda do |path, params|
        fetch_calls << { path: path, params: params }
        if path == BinanceClient::INCOME_PATH
          [ { "symbol" => "BTCUSDC" }, { "symbol" => "BTCUSDT" } ]
        elsif path == BinanceClient::POSITION_RISK_PATH
          []
        elsif path == BinanceClient::USER_TRADES_PATH
          []
        else
          []
        end
      end
      client.stub(:signed_get, stub) do
        client.fetch_my_trades(since: 1.day.ago)
      end
      user_trade_calls = fetch_calls.select { |c| c[:path] == BinanceClient::USER_TRADES_PATH }
      assert user_trade_calls.none? { |c| c[:params]["symbol"] == "BTCUSDC" },
        "Should not fetch userTrades for USDC when not in whitelist"
      assert user_trade_calls.any? { |c| c[:params]["symbol"] == "BTCUSDT" },
        "Should still fetch userTrades for USDT"
    end

    test "fetch_my_trades uses default whitelist when allowed_quote_currencies is nil" do
      client = BinanceClient.new(api_key: "k", api_secret: "s", allowed_quote_currencies: nil)
      fetch_calls = []
      stub = lambda do |path, params|
        fetch_calls << { path: path, params: params }
        if path == BinanceClient::INCOME_PATH
          [ { "symbol" => "BTCUSDC" }, { "symbol" => "BTCUSDT" } ]
        elsif path == BinanceClient::POSITION_RISK_PATH
          []
        else
          []
        end
      end
      client.stub(:signed_get, stub) do
        client.fetch_my_trades(since: 1.day.ago)
      end
      user_trade_symbols = fetch_calls.select { |c| c[:path] == BinanceClient::USER_TRADES_PATH }.map { |c| c[:params]["symbol"] }
      assert_includes user_trade_symbols, "BTCUSDC", "USDC in default whitelist"
      assert_includes user_trade_symbols, "BTCUSDT", "USDT in default whitelist"
    end

    test "leverage_by_symbol returns app symbol => leverage from positionRisk" do
      position_risk = [
        { "symbol" => "BTCUSDT", "positionAmt" => "0.1", "leverage" => "5" },
        { "symbol" => "ETHUSDT", "positionAmt" => "0", "leverage" => "10" }
      ]
      @client.stub(:signed_get, ->(path, _params) {
        return position_risk if path == BinanceClient::POSITION_RISK_PATH
        []
      }) do
        result = @client.leverage_by_symbol
        assert_equal 5, result["BTC-USDT"]
        assert_equal 10, result["ETH-USDT"]
        assert_equal 2, result.size
      end
    end

    private

    def fake_response(code:, body:, headers: {})
      res = Object.new
      res.define_singleton_method(:code) { code.to_s }
      res.define_singleton_method(:body) { body }
      res.define_singleton_method(:[]) { |k| headers[k] }
      res
    end

    def stub_http_response(code:, body:, headers: {})
      response = fake_response(code: code, body: body, headers: headers)
      http = build_fake_http(response: response)
      Net::HTTP.stub(:new, http) { yield }
    end

    def stub_http_timeout(exception_klass)
      http = build_fake_http(raise_on_request: exception_klass.new("timeout"))
      Net::HTTP.stub(:new, http) { yield }
    end

    def build_fake_http(response: nil, raise_on_request: nil)
      fake = Object.new
      fake.define_singleton_method(:use_ssl=) { |_| }
      fake.define_singleton_method(:open_timeout=) { |_| }
      fake.define_singleton_method(:read_timeout=) { |_| }
      fake.define_singleton_method(:request) do |_req|
        raise raise_on_request if raise_on_request
        response
      end
      fake
    end
  end
end
