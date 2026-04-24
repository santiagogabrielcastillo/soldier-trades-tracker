# frozen_string_literal: true

require "test_helper"

module Stocks
  class ArgentineCurrentPriceFetcherTest < ActiveSupport::TestCase
    setup do
      Rails.cache.clear
      @user = users(:one)
    end

    test "returns empty hash for blank tickers" do
      assert_equal({}, ArgentineCurrentPriceFetcher.call(tickers: [], user: @user))
    end

    test "returns empty hash when no IOL credentials configured" do
      assert_equal({}, ArgentineCurrentPriceFetcher.call(tickers: [ "AAPL" ], user: @user))
    end

    test "returns prices when credentials configured" do
      @user.user_api_keys.create!(provider: "iol", key: "user@example.com", secret: "pass")
      stub_client = Object.new
      stub_client.define_singleton_method(:quote) { |ticker| ticker == "AAPL" ? BigDecimal("1500.0") : nil }
      ArgentineCurrentPriceFetcher.stub(:build_client, stub_client) do
        result = ArgentineCurrentPriceFetcher.call(tickers: [ "AAPL" ], user: @user)
        assert_equal BigDecimal("1500.0"), result["AAPL"]
      end
    end

    test "omits tickers with nil price" do
      @user.user_api_keys.create!(provider: "iol", key: "user@example.com", secret: "pass")
      stub_client = Object.new
      stub_client.define_singleton_method(:quote) { |_| nil }
      ArgentineCurrentPriceFetcher.stub(:build_client, stub_client) do
        assert_equal({}, ArgentineCurrentPriceFetcher.call(tickers: [ "UNKNOWN" ], user: @user))
      end
    end
  end
end
