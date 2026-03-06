# frozen_string_literal: true

require "test_helper"

module Exchanges
  class ProviderForAccountTest < ActiveSupport::TestCase
    test "supported? returns true for bingx with credentials" do
      account = OpenStruct.new(provider_type: "bingx", api_key: "k", api_secret: "s")
      assert ProviderForAccount.new(account).supported?
    end

    test "supported? returns true for binance with credentials" do
      account = OpenStruct.new(provider_type: "binance", api_key: "k", api_secret: "s")
      assert ProviderForAccount.new(account).supported?
    end

    test "supported? returns false for unknown provider" do
      account = OpenStruct.new(provider_type: "other", api_key: "k", api_secret: "s")
      refute ProviderForAccount.new(account).supported?
    end

    test "supported? returns false when credentials blank" do
      account = OpenStruct.new(provider_type: "bingx", api_key: "", api_secret: "s")
      refute ProviderForAccount.new(account).supported?
    end

    test "client returns a client for bingx that responds to fetch_my_trades" do
      account = OpenStruct.new(provider_type: "bingx", api_key: "k", api_secret: "s")
      client = ProviderForAccount.new(account).client
      assert client
      assert_respond_to client, :fetch_my_trades
    end

    test "client returns a client for binance that responds to fetch_my_trades" do
      account = OpenStruct.new(provider_type: "binance", api_key: "k", api_secret: "s")
      client = ProviderForAccount.new(account).client
      assert client
      assert_respond_to client, :fetch_my_trades
    end

    test "client returns nil for unsupported provider" do
      account = OpenStruct.new(provider_type: "other", api_key: "k", api_secret: "s")
      assert_nil ProviderForAccount.new(account).client
    end

    test "ping? returns true for unsupported provider (no ping required)" do
      assert ProviderForAccount.ping?(provider_type: "other", api_key: "k", api_secret: "s")
    end
  end
end
