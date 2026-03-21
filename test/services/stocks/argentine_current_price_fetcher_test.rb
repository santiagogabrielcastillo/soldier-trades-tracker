# frozen_string_literal: true

require "test_helper"

module Stocks
  class ArgentineCurrentPriceFetcherTest < ActiveSupport::TestCase
    test "returns empty hash when tickers list is empty" do
      result = ArgentineCurrentPriceFetcher.call(tickers: [])
      assert_equal({}, result)
    end

    test "returns empty hash when IOL credentials are missing" do
      stub_client = Object.new
      def stub_client.quote(_ticker) = nil

      ArgentineCurrentPriceFetcher.stub(:argentine_client, stub_client) do
        result = ArgentineCurrentPriceFetcher.call(tickers: %w[AAPL MSFT])
        assert_equal({}, result)
      end
    end

    test "returns prices from the client when provider is configured" do
      stub_client = Minitest::Mock.new
      stub_client.expect(:quote, BigDecimal("12500"), [ "AAPL" ])
      stub_client.expect(:quote, nil, [ "MSFT" ])

      ArgentineCurrentPriceFetcher.stub(:argentine_client, stub_client) do
        result = ArgentineCurrentPriceFetcher.call(tickers: %w[AAPL MSFT])
        assert_equal BigDecimal("12500"), result["AAPL"]
        assert_nil result["MSFT"]
      end

      stub_client.verify
    end

    test "omits tickers with nil price from results" do
      stub_client = Object.new
      def stub_client.quote(_ticker) = nil

      ArgentineCurrentPriceFetcher.stub(:argentine_client, stub_client) do
        result = ArgentineCurrentPriceFetcher.call(tickers: %w[AAPL])
        assert_equal({}, result)
      end
    end

    test "deduplicates and upcases tickers" do
      called_tickers = []
      stub_client = Object.new
      stub_client.define_singleton_method(:quote) do |ticker|
        called_tickers << ticker
        nil
      end

      ArgentineCurrentPriceFetcher.stub(:argentine_client, stub_client) do
        ArgentineCurrentPriceFetcher.call(tickers: %w[aapl AAPL aapl])
      end

      assert_equal [ "AAPL" ], called_tickers
    end
  end
end
