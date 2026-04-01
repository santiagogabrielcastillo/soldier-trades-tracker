# frozen_string_literal: true

require "test_helper"

module Allocations
  class SummaryServiceTest < ActiveSupport::TestCase
    # A minimal open position stub that satisfies the interface used by compute_all_spot_usd
    OpenPosition = Struct.new(:token, :balance, keyword_init: true) do
      def open? = true
    end

    test "fetches spot prices exactly once regardless of number of spot accounts" do
      user = users(:one)
      # Ensure two spot accounts exist so we have multiple accounts to process
      user.spot_accounts.find_or_create_by!(name: "Account A", default: false)
      user.spot_accounts.find_or_create_by!(name: "Account B", default: false)

      fetch_call_count = 0
      price_stub = lambda do |**|
        fetch_call_count += 1
        { "BTC" => BigDecimal("50000") }
      end

      # Each account has one open BTC position — this would trigger N price fetches
      # under the old per-account implementation, but only 1 under the batched one.
      open_position = OpenPosition.new(token: "BTC", balance: BigDecimal("0.1"))

      Spot::PositionStateService.stub(:call, [ open_position ]) do
        Spot::CurrentPriceFetcher.stub(:call, price_stub) do
          SummaryService.call(user: user)
        end
      end

      assert_operator fetch_call_count, :<=, 1,
        "Expected at most 1 price fetch call, got #{fetch_call_count}"
    end
  end
end
