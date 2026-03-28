# frozen_string_literal: true

require "test_helper"

class ExchangeAccounts::SyncServiceTest < ActiveSupport::TestCase
  test "historic sync uses 2018-01-01 as the since date regardless of account state" do
    account = exchange_accounts(:one)
    account.last_synced_at = 1.day.ago
    service = ExchangeAccounts::SyncService.new(account, historic: true)
    client = Exchanges::BinanceClient.new(api_key: "k", api_secret: "s")

    since = service.send(:since_for_fetch, client)

    assert_equal Time.new(2018, 1, 1).utc, since
  end

  test "non-historic sync uses last_synced_at for incremental fetch" do
    account = exchange_accounts(:one)
    account.last_synced_at = 3.days.ago
    service = ExchangeAccounts::SyncService.new(account, historic: false)
    client = Exchanges::BingxClient.new(api_key: "k", api_secret: "s")

    since = service.send(:since_for_fetch, client)

    assert_in_delta 3.days.ago.to_i, since.to_i, 5
  end

  test "non-historic first binance sync uses 6-month lookback" do
    account = exchange_accounts(:one)
    account.provider_type = "binance"
    account.last_synced_at = nil
    account.linked_at = 2.years.ago
    service = ExchangeAccounts::SyncService.new(account, historic: false)
    client = Exchanges::BinanceClient.new(api_key: "k", api_secret: "s")

    account.trades.destroy_all

    since = service.send(:since_for_fetch, client)

    assert since > 7.months.ago, "Expected since to be within 7 months, got #{since}"
    assert since < 5.months.ago, "Expected since to be older than 5 months, got #{since}"
  end
end
