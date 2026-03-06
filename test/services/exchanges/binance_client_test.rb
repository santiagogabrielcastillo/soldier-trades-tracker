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
          [{ "symbol" => "BTCUSDT", "positionAmt" => "0.1" }]
        elsif path == BinanceClient::USER_TRADES_PATH && params["symbol"] == "BTCUSDT"
          [raw_trade]
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
