# frozen_string_literal: true

require "test_helper"

module Stocks
  class CurrentPriceFetcherTest < ActiveSupport::TestCase
    setup do
      Rails.cache.clear
      @user = users(:one)
    end

    test "returns empty hash for blank tickers" do
      assert_equal({}, CurrentPriceFetcher.call(tickers: [], user: @user))
    end

    test "returns empty hash when no finnhub key configured" do
      assert_equal({}, CurrentPriceFetcher.call(tickers: ["AAPL"], user: @user))
    end

    test "returns prices for valid tickers" do
      @user.user_api_keys.create!(provider: "finnhub", key: "test_key")
      stub_client = stub_finnhub("AAPL" => BigDecimal("180.0"))
      CurrentPriceFetcher.stub(:build_client, stub_client) do
        result = CurrentPriceFetcher.call(tickers: ["AAPL"], user: @user)
        assert_equal BigDecimal("180.0"), result["AAPL"]
      end
    end

    test "caches results for 5 minutes" do
      @user.user_api_keys.create!(provider: "finnhub", key: "test_key")
      call_count = 0
      stub_client = Object.new
      stub_client.define_singleton_method(:quote) { |_| call_count += 1; BigDecimal("180.0") }
      CurrentPriceFetcher.stub(:build_client, stub_client) do
        CurrentPriceFetcher.call(tickers: ["AAPL"], user: @user)
        CurrentPriceFetcher.call(tickers: ["AAPL"], user: @user)
      end
      assert_equal 1, call_count
    end

    test "omits tickers with nil price" do
      @user.user_api_keys.create!(provider: "finnhub", key: "test_key")
      stub_client = Object.new
      stub_client.define_singleton_method(:quote) { |_| nil }
      CurrentPriceFetcher.stub(:build_client, stub_client) do
        assert_equal({}, CurrentPriceFetcher.call(tickers: ["UNKNOWN"], user: @user))
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
