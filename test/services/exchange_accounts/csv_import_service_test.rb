# frozen_string_literal: true

require "test_helper"

class ExchangeAccounts::CsvImportServiceTest < ActiveSupport::TestCase
  TWO_ROW_CSV = <<~CSV
    Uid,Time,Symbol,Side,Price,Quantity,Amount,Fee,Realized Profit,Buyer,Maker,Trade ID,Order ID
    862706699,26-03-17 09:34:12,BTCUSDT,BUY,73822.3,0.01,738.223,0.29528919 USDT,0,true,false,419925075,49172439177
    862706699,26-01-31 13:17:22,BTCUSDT,SELL,80600.2,0.007,564.2014,0.28210070 USDT,97.84870666,true,false,7161708169,896310121516
  CSV

  setup do
    @account = exchange_accounts(:one)
    @account.update_column(:provider_type, "binance")
    @account.trades.destroy_all
  end

  test "creates new trades and returns correct result" do
    result = ExchangeAccounts::CsvImportService.call(
      exchange_account: @account,
      csv_io: StringIO.new(TWO_ROW_CSV)
    )

    assert_equal 2, result.created
    assert_equal 0, result.updated
    assert_equal 0, result.skipped
    assert_empty result.errors
  end

  test "persists trades with correct attributes" do
    ExchangeAccounts::CsvImportService.call(
      exchange_account: @account,
      csv_io: StringIO.new(TWO_ROW_CSV)
    )

    trade = @account.trades.find_by(exchange_reference_id: "419925075")
    assert trade
    assert_equal "BTC-USDT",             trade.symbol
    assert_equal "buy",                  trade.side
    assert_equal Time.utc(2026, 3, 17),  trade.executed_at
    assert trade.fee.present?
    assert trade.net_amount.present?
  end

  test "re-importing the same CSV updates existing trades (idempotent)" do
    ExchangeAccounts::CsvImportService.call(exchange_account: @account, csv_io: StringIO.new(TWO_ROW_CSV))

    result = ExchangeAccounts::CsvImportService.call(
      exchange_account: @account,
      csv_io: StringIO.new(TWO_ROW_CSV)
    )

    assert_equal 0, result.created
    assert_equal 2, result.updated
    assert_equal 2, @account.trades.count
  end

  test "does not update last_synced_at" do
    original = @account.last_synced_at
    ExchangeAccounts::CsvImportService.call(exchange_account: @account, csv_io: StringIO.new(TWO_ROW_CSV))
    assert_equal original, @account.reload.last_synced_at
  end

  test "does not create a SyncRun record" do
    assert_no_difference "SyncRun.count" do
      ExchangeAccounts::CsvImportService.call(exchange_account: @account, csv_io: StringIO.new(TWO_ROW_CSV))
    end
  end

  test "rebuilds positions after import" do
    ExchangeAccounts::CsvImportService.call(exchange_account: @account, csv_io: StringIO.new(TWO_ROW_CSV))
    assert @account.reload.positions.any?
  end

  test "raises ArgumentError when CSV ParseError is raised by parser" do
    bad_csv = "Symbol,Side\nBTCUSDT,BUY\n"
    assert_raises(ArgumentError) do
      ExchangeAccounts::CsvImportService.call(exchange_account: @account, csv_io: StringIO.new(bad_csv))
    end
  end

  test "counts skipped when RecordNotUnique is raised" do
    original_save = Trade.instance_method(:save!)
    Trade.define_method(:save!) { raise ActiveRecord::RecordNotUnique }

    result = ExchangeAccounts::CsvImportService.call(
      exchange_account: @account,
      csv_io: StringIO.new(TWO_ROW_CSV)
    )

    assert_equal 0, result.created
    assert_equal 2, result.skipped
  ensure
    Trade.define_method(:save!, original_save)
  end

  test "appends error message when RecordInvalid is raised" do
    original_save = Trade.instance_method(:save!)
    Trade.define_method(:save!) { raise ActiveRecord::RecordInvalid.new(Trade.new) }

    result = ExchangeAccounts::CsvImportService.call(
      exchange_account: @account,
      csv_io: StringIO.new(TWO_ROW_CSV)
    )

    assert_equal 0, result.created
    assert_equal 2, result.errors.size
    assert result.errors.first.include?("Row")
  ensure
    Trade.define_method(:save!, original_save)
  end
end
