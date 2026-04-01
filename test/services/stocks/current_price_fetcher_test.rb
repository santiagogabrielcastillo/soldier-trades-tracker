# frozen_string_literal: true

require "test_helper"

module Stocks
  class CurrentPriceFetcherTest < ActiveSupport::TestCase
    setup do
      Rails.cache.clear
    end

    test "returns empty hash for blank tickers" do
      assert_equal({}, CurrentPriceFetcher.call(tickers: []))
    end

    test "returns prices for valid tickers" do
      stub_client = stub_finnhub("AAPL" => BigDecimal("180.0"))

      CurrentPriceFetcher.stub(:finnhub_client, stub_client) do
        result = CurrentPriceFetcher.call(tickers: ["AAPL"])
        assert_equal BigDecimal("180.0"), result["AAPL"]
      end
    end

    test "caches results for 5 minutes" do
      call_count = 0
      stub_client = Object.new
      stub_client.define_singleton_method(:quote) do |_ticker|
        call_count += 1
        BigDecimal("180.0")
      end

      CurrentPriceFetcher.stub(:finnhub_client, stub_client) do
        CurrentPriceFetcher.call(tickers: ["AAPL"])
        CurrentPriceFetcher.call(tickers: ["AAPL"])
      end

      assert_equal 1, call_count, "Expected Finnhub to be called once (second call from cache)"
    end

    test "omits tickers with nil price" do
      stub_client = Object.new
      stub_client.define_singleton_method(:quote) { |_ticker| nil }

      CurrentPriceFetcher.stub(:finnhub_client, stub_client) do
        result = CurrentPriceFetcher.call(tickers: ["UNKNOWN"])
        assert_equal({}, result)
      end
    end

    test "normalizes and deduplicates tickers" do
      call_count = 0
      stub_client = Object.new
      stub_client.define_singleton_method(:quote) do |_ticker|
        call_count += 1
        BigDecimal("180.0")
      end

      CurrentPriceFetcher.stub(:finnhub_client, stub_client) do
        result = CurrentPriceFetcher.call(tickers: ["aapl", "AAPL", "aapl"])
        assert_equal 1, call_count, "Expected Finnhub to be called once for deduplicated tickers"
        assert_equal BigDecimal("180.0"), result["AAPL"]
      end
    end

    test "returns prices for multiple tickers" do
      stub_client = stub_finnhub("AAPL" => BigDecimal("180.0"), "MSFT" => BigDecimal("420.0"))

      CurrentPriceFetcher.stub(:finnhub_client, stub_client) do
        result = CurrentPriceFetcher.call(tickers: ["AAPL", "MSFT"])
        assert_equal BigDecimal("180.0"), result["AAPL"]
        assert_equal BigDecimal("420.0"), result["MSFT"]
      end
    end

    private

    def stub_finnhub(prices_by_ticker)
      stub_client = Object.new
      stub_client.define_singleton_method(:quote) { |ticker| prices_by_ticker[ticker] }
      stub_client
    end
  end
end
