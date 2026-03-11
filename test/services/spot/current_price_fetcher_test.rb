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

    test "returns empty when user has no exchange account" do
      @user.exchange_accounts.destroy_all
      result = CurrentPriceFetcher.call(user: @user, tokens: ["BTC"])
      assert_equal({}, result)
    end

    test "calls Binance SpotTickerFetcher when user has Binance account" do
      @user.exchange_accounts.destroy_all
      ExchangeAccountKeyValidator.stub(:read_only?, true) do
        @user.exchange_accounts.create!(provider_type: "binance", api_key: "k", api_secret: "s")
      end
      stub_fetch = { "BTC" => BigDecimal("50000"), "ETH" => BigDecimal("3000") }
      Exchanges::Binance::SpotTickerFetcher.stub(:fetch_prices, stub_fetch) do
        result = CurrentPriceFetcher.call(user: @user, tokens: %w[BTC ETH])
        assert_equal BigDecimal("50000"), result["BTC"]
        assert_equal BigDecimal("3000"), result["ETH"]
      end
    end
  end
end
