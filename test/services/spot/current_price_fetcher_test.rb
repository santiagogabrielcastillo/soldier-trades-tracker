# frozen_string_literal: true

require "test_helper"

module Spot
  class CurrentPriceFetcherTest < ActiveSupport::TestCase
    setup do
      Rails.cache.clear
      @user = users(:one)
    end

    test "returns empty hash for blank tokens" do
      assert_equal({}, CurrentPriceFetcher.call(tokens: [], user: @user))
    end

    test "returns prices when fetcher succeeds" do
      prices = { "BTC" => BigDecimal("60000") }
      Exchanges::Binance::SpotTickerFetcher.stub(:fetch_prices, prices) do
        result = CurrentPriceFetcher.call(tokens: ["BTC"], user: @user)
        assert_equal BigDecimal("60000"), result["BTC"]
      end
    end

    test "caches results" do
      call_count = 0
      stub_fetcher = Object.new
      stub_fetcher.define_singleton_method(:fetch_prices) { |**| call_count += 1; { "BTC" => BigDecimal("60000") } }
      Exchanges::Binance::SpotTickerFetcher.stub(:new, stub_fetcher) do
        CurrentPriceFetcher.call(tokens: ["BTC"], user: @user)
        CurrentPriceFetcher.call(tokens: ["BTC"], user: @user)
      end
      assert_equal 1, call_count
    end

    test "normalizes and deduplicates tokens" do
      call_count = 0
      stub_fetcher = Object.new
      stub_fetcher.define_singleton_method(:fetch_prices) { |**| call_count += 1; {} }
      Exchanges::Binance::SpotTickerFetcher.stub(:new, stub_fetcher) do
        CurrentPriceFetcher.call(tokens: ["btc", "BTC", "Btc"], user: @user)
      end
      assert_equal 1, call_count
    end
  end
end
