# frozen_string_literal: true

require "test_helper"

module Spot
  class CurrentPriceFetcherTest < ActiveSupport::TestCase
    setup do
      Rails.cache.clear
    end

    test "returns empty hash for blank tokens" do
      assert_equal({}, CurrentPriceFetcher.call(tokens: []))
    end

    test "calls Binance SpotTickerFetcher and returns prices" do
      stub_fetch = { "BTC" => BigDecimal("50000"), "ETH" => BigDecimal("3000") }
      Exchanges::Binance::SpotTickerFetcher.stub(:fetch_prices, stub_fetch) do
        result = CurrentPriceFetcher.call(tokens: %w[BTC ETH])
        assert_equal BigDecimal("50000"), result["BTC"]
        assert_equal BigDecimal("3000"), result["ETH"]
      end
    end

    test "caches results for 2 minutes" do
      call_count = 0
      fetcher_stub = lambda do |**|
        call_count += 1
        { "BTC" => BigDecimal("50000") }
      end

      Exchanges::Binance::SpotTickerFetcher.stub(:fetch_prices, fetcher_stub) do
        CurrentPriceFetcher.call(tokens: ["BTC"])
        CurrentPriceFetcher.call(tokens: ["BTC"])
      end

      assert_equal 1, call_count, "Expected SpotTickerFetcher to be called once (second from cache)"
    end

    test "cache key is order-independent" do
      call_count = 0
      fetcher_stub = lambda do |**|
        call_count += 1
        {}
      end

      Exchanges::Binance::SpotTickerFetcher.stub(:fetch_prices, fetcher_stub) do
        CurrentPriceFetcher.call(tokens: ["ETH", "BTC"])
        CurrentPriceFetcher.call(tokens: ["BTC", "ETH"])
      end

      assert_equal 1, call_count, "Same token set in different order should share cache"
    end

    test "normalizes and deduplicates mixed-case tokens" do
      call_count = 0
      fetcher_stub = lambda do |tokens:|
        call_count += 1
        tokens.index_with { BigDecimal("1") }
      end

      Exchanges::Binance::SpotTickerFetcher.stub(:fetch_prices, fetcher_stub) do
        result = CurrentPriceFetcher.call(tokens: ["btc", "BTC", "Btc"])
        assert_equal 1, call_count, "Expected SpotTickerFetcher to be called once for deduplicated tokens"
        assert_includes result.keys, "BTC"
        assert_equal 1, result.keys.length
      end
    end
  end
end
