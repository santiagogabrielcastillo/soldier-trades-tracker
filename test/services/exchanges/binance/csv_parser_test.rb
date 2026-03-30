# frozen_string_literal: true

require "test_helper"

class Exchanges::Binance::CsvParserTest < ActiveSupport::TestCase
  VALID_CSV = <<~CSV
    Uid,Time,Symbol,Side,Price,Quantity,Amount,Fee,Realized Profit,Buyer,Maker,Trade ID,Order ID
    862706699,26-03-17 09:34:12,BTCUSDC,BUY,73822.3,0.01,738.223,0.29528919 USDC,0.28699999,true,false,419925075,49172439177
    862706699,26-01-31 13:17:22,BTCUSDT,BUY,80600.2,0.007,564.2014,0.28210070 USDT,97.84870666,true,false,7161708169,896310121516
    862706699,26-01-19 11:52:00,COMPUSDT,SELL,25.23,0.436,11.00028,0.00550014 USDT,-4.43848,false,false,439592093,12425682460
  CSV

  test "parses exchange_reference_id, symbol, side, price, quantity, fee, executed_at" do
    trades = Exchanges::Binance::CsvParser.call(StringIO.new(VALID_CSV))
    assert_equal 3, trades.size

    t = trades.first
    assert_equal "419925075",              t[:exchange_reference_id]
    assert_equal "BTC-USDC",              t[:symbol]
    assert_equal "buy",                   t[:side]
    assert_equal BigDecimal("73822.3"),   t[:price]
    assert_equal BigDecimal("0.01"),      t[:quantity]
    assert_equal BigDecimal("0.29528919"), t[:fee_from_exchange]
    assert_equal Time.utc(2026, 3, 17),   t[:executed_at]
  end

  test "normalizes BTCUSDT symbol to BTC-USDT" do
    trades = Exchanges::Binance::CsvParser.call(StringIO.new(VALID_CSV))
    assert_equal "BTC-USDT", trades[1][:symbol]
  end

  test "normalizes COMPUSDT to COMP-USDT and sell to lowercase" do
    trades = Exchanges::Binance::CsvParser.call(StringIO.new(VALID_CSV))
    assert_equal "COMP-USDT", trades[2][:symbol]
    assert_equal "sell",       trades[2][:side]
  end

  test "sets positionSide BOTH in raw_payload" do
    trades = Exchanges::Binance::CsvParser.call(StringIO.new(VALID_CSV))
    assert_equal "BOTH", trades.first[:raw_payload]["positionSide"]
  end

  test "sets realizedPnl in raw_payload from Realized Profit column" do
    trades = Exchanges::Binance::CsvParser.call(StringIO.new(VALID_CSV))
    assert_equal "0.28699999", trades.first[:raw_payload]["realizedPnl"]
    assert_equal "-4.43848",   trades[2][:raw_payload]["realizedPnl"]
  end

  test "parses fee from combined amount+currency string" do
    trades = Exchanges::Binance::CsvParser.call(StringIO.new(VALID_CSV))
    assert_equal BigDecimal("0.29528919"), trades[0][:fee_from_exchange]
    assert_equal BigDecimal("0.28210070"), trades[1][:fee_from_exchange]
  end

  test "stores only the date portion of Time (midnight UTC)" do
    trades = Exchanges::Binance::CsvParser.call(StringIO.new(VALID_CSV))
    assert_equal Time.utc(2026, 1, 31), trades[1][:executed_at]
    assert_equal 0, trades[1][:executed_at].hour
  end

  test "skips rows where Trade ID is blank" do
    csv = VALID_CSV.lines.first +
          "862706699,26-03-17 09:34:12,BTCUSDT,BUY,100,1,100,0.1 USDT,0,true,false,,123\n"
    trades = Exchanges::Binance::CsvParser.call(StringIO.new(csv))
    assert_equal 0, trades.size
  end

  test "skips rows with unparseable date" do
    csv = VALID_CSV.lines.first +
          "862706699,NOTADATE,BTCUSDT,BUY,100,1,100,0.1 USDT,0,true,false,999,888\n"
    trades = Exchanges::Binance::CsvParser.call(StringIO.new(csv))
    assert_equal 0, trades.size
  end

  test "skips rows where side is not buy or sell" do
    csv = VALID_CSV.lines.first +
          "862706699,26-03-17 09:34:12,BTCUSDT,TRANSFER,100,1,100,0.1 USDT,0,true,false,999,888\n"
    trades = Exchanges::Binance::CsvParser.call(StringIO.new(csv))
    assert_equal 0, trades.size
  end

  test "raises ParseError when required headers are missing" do
    bad_csv = "Symbol,Side\nBTCUSDT,BUY\n"
    assert_raises(Exchanges::Binance::CsvParser::ParseError) do
      Exchanges::Binance::CsvParser.call(StringIO.new(bad_csv))
    end
  end

  test "ParseError message names the missing columns" do
    bad_csv = "Symbol,Side,Price\nBTCUSDT,BUY,100\n"
    error = assert_raises(Exchanges::Binance::CsvParser::ParseError) do
      Exchanges::Binance::CsvParser.call(StringIO.new(bad_csv))
    end
    assert_match(/Trade ID/, error.message)
  end
end
