# frozen_string_literal: true

require "test_helper"

module Exchanges
  module Binance
    class TradeNormalizerTest < ActiveSupport::TestCase
      test "normalize_symbol converts BTCUSDT to BTC-USDT" do
        assert_equal "BTC-USDT", TradeNormalizer.normalize_symbol("BTCUSDT")
      end

      test "normalize_symbol converts ETHUSDT to ETH-USDT" do
        assert_equal "ETH-USDT", TradeNormalizer.normalize_symbol("ETHUSDT")
      end

      test "normalize_symbol converts to USDC pair" do
        assert_equal "BTC-USDC", TradeNormalizer.normalize_symbol("BTCUSDC")
      end

      test "normalize_symbol returns nil for blank" do
        assert_nil TradeNormalizer.normalize_symbol("")
        assert_nil TradeNormalizer.normalize_symbol(nil)
      end

      test "user_trade_to_hash returns nil when id blank" do
        raw = { "symbol" => "BTCUSDT", "side" => "BUY", "price" => "50000", "qty" => "0.01", "time" => (Time.now.to_i * 1000) }
        assert_nil TradeNormalizer.user_trade_to_hash(raw)
      end

      test "user_trade_to_hash returns nil when time blank" do
        raw = { "id" => "123", "symbol" => "BTCUSDT", "side" => "BUY", "price" => "50000", "qty" => "0.01" }
        assert_nil TradeNormalizer.user_trade_to_hash(raw)
      end

      test "user_trade_to_hash maps required fields and normalizes symbol" do
        time_ms = (Time.now.to_i - 3600) * 1000
        raw = {
          "id" => "trade_abc",
          "symbol" => "BTCUSDT",
          "side" => "BUY",
          "price" => "50000.25",
          "qty" => "0.01",
          "commission" => "-0.07819010",
          "realizedPnl" => "10.5",
          "positionSide" => "LONG",
          "time" => time_ms
        }
        h = TradeNormalizer.user_trade_to_hash(raw)
        assert h
        assert_equal "trade_abc", h[:exchange_reference_id]
        assert_equal "BTC-USDT", h[:symbol]
        assert_equal "buy", h[:side]
        assert_equal BigDecimal("50000.25"), h[:price]
        assert_equal BigDecimal("0.01"), h[:quantity]
        assert_equal BigDecimal("0.07819010"), h[:fee_from_exchange], "commission should be absolute value"
        assert_equal Time.at(time_ms / 1000.0).utc, h[:executed_at]
        assert_equal raw, h[:raw_payload]
        assert_equal "LONG", h[:position_id]
      end

      test "user_trade_to_hash uses absolute value for commission" do
        raw = { "id" => "1", "symbol" => "ETHUSDT", "side" => "SELL", "price" => "3000", "qty" => "1", "commission" => "-1.5", "time" => (Time.now.to_i * 1000) }
        h = TradeNormalizer.user_trade_to_hash(raw)
        assert_equal BigDecimal("1.5"), h[:fee_from_exchange]
      end
    end
  end
end
