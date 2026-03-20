# frozen_string_literal: true

require "test_helper"

module Exchanges
  module Bingx
    class TickerFetcherTest < ActiveSupport::TestCase
      test "fetch_prices returns empty hash for empty symbols" do
        assert_equal({}, TickerFetcher.fetch_prices(symbols: []))
      end

      test "fetch_prices returns empty hash for nil symbols" do
        assert_equal({}, TickerFetcher.fetch_prices(symbols: nil))
      end

      test "fetch_prices returns price for successful response" do
        stub_ticker_response("BTC-USDT", { "data" => { "lastPrice" => "97500.5" } }) do
          result = TickerFetcher.fetch_prices(symbols: [ "BTC-USDT" ])
          assert_equal 1, result.size
          assert_equal BigDecimal("97500.5"), result["BTC-USDT"]
        end
      end

      test "fetch_prices accepts data at top level with lastPrice" do
        stub_ticker_response("ETH-USDT", { "lastPrice" => "3500.25" }) do
          result = TickerFetcher.fetch_prices(symbols: [ "ETH-USDT" ])
          assert_equal BigDecimal("3500.25"), result["ETH-USDT"]
        end
      end

      test "fetch_prices skips symbol on non-200 and returns rest" do
        responses = [
          fake_response("500", "{}"),
          fake_response("200", { "data" => { "lastPrice" => "3500" } }.to_json)
        ]
        http = build_http_with_responses(responses)
        Net::HTTP.stub(:new, http) do
          result = TickerFetcher.fetch_prices(symbols: [ "BTC-USDT", "ETH-USDT" ])
          assert_equal 1, result.size
          assert_equal BigDecimal("3500"), result["ETH-USDT"]
        end
      end

      test "fetch_prices skips symbol on JSON parse error" do
        stub_ticker_response("BTC-USDT", nil, code: "200", body_raw: "not json") do
          result = TickerFetcher.fetch_prices(symbols: [ "BTC-USDT" ])
          assert_equal({}, result)
        end
      end

      test "fetch_prices deduplicates symbols" do
        stub_ticker_response("BTC-USDT", { "data" => { "lastPrice" => "100" } }) do
          result = TickerFetcher.fetch_prices(symbols: [ "BTC-USDT", "BTC-USDT" ])
          assert_equal 1, result.size
          assert_equal BigDecimal("100"), result["BTC-USDT"]
        end
      end

      private

      def fake_response(code, body)
        res = Object.new
        res.define_singleton_method(:code) { code.to_s }
        res.define_singleton_method(:body) { body }
        res
      end

      def build_http_with_responses(response_list)
        index = 0
        http = Object.new
        http.define_singleton_method(:use_ssl=) { |_| }
        http.define_singleton_method(:open_timeout=) { |_| }
        http.define_singleton_method(:read_timeout=) { |_| }
        http.define_singleton_method(:request) do |_|
          r = response_list[index]
          index += 1
          r
        end
        http
      end

      def stub_ticker_response(_symbol, body = nil, code: "200", body_raw: nil)
        response_body = body_raw || (body.is_a?(Hash) ? body.to_json : body.to_s)
        res = fake_response(code, response_body)
        http = build_http_with_responses([ res ])
        Net::HTTP.stub(:new, http) { yield }
      end
    end
  end
end
