# frozen_string_literal: true

require "test_helper"

module Spot
  class CurrentPriceFetcherTest < ActiveSupport::TestCase
    setup do
      @user = users(:one)
    end

    test "returns empty when no tokens" do
      result = CurrentPriceFetcher.call(user: @user, tokens: [])
      assert_equal({}, result)
    end

    test "calls Binance SpotTickerFetcher regardless of exchange accounts" do
      stub_fetch = { "BTC" => BigDecimal("50000"), "ETH" => BigDecimal("3000") }
      Exchanges::Binance::SpotTickerFetcher.stub(:fetch_prices, stub_fetch) do
        result = CurrentPriceFetcher.call(user: @user, tokens: %w[BTC ETH])
        assert_equal BigDecimal("50000"), result["BTC"]
        assert_equal BigDecimal("3000"), result["ETH"]
      end
    end

    test "calls Binance SpotTickerFetcher even when user has no exchange accounts" do
      @user.exchange_accounts.destroy_all
      stub_fetch = { "BTC" => BigDecimal("50000") }
      Exchanges::Binance::SpotTickerFetcher.stub(:fetch_prices, stub_fetch) do
        result = CurrentPriceFetcher.call(user: @user, tokens: ["BTC"])
        assert_equal BigDecimal("50000"), result["BTC"]
      end
    end
  end
end
