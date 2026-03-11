# frozen_string_literal: true

require "test_helper"

module Spot
  class CsvRowParserTest < ActiveSupport::TestCase
    test "parse_row normalizes token and side" do
      row = {
        "Date (UTC-3:00)" => "2026-01-14 10:05:00",
        "Token" => "  aave  ",
        "Type" => "  BUY  ",
        "Price (USD)" => "174.52",
        "Amount" => "2.292",
        "Total value (USD)" => "400.00",
        "Fee" => "--",
        "Fee Currency" => "",
        "Notes" => ""
      }
      result = CsvRowParser.parse_row(row, row_number: 2)
      assert_equal "AAVE", result[:token]
      assert_equal "buy", result[:side]
      assert result[:executed_at].utc?
      assert_equal BigDecimal("174.52"), result[:price_usd]
      assert_equal BigDecimal("2.292"), result[:amount]
      assert_equal BigDecimal("400.00"), result[:total_value_usd]
      assert_equal 64, result[:row_signature].length
    end

    test "parse_row strips commas from amount" do
      row = {
        "Date (UTC-3:00)" => "2026-01-19 10:40:00",
        "Token" => "LDO",
        "Type" => "sell",
        "Price (USD)" => "0.5454",
        "Amount" => "1,150.01",
        "Total value (USD)" => "627.22",
        "Fee" => "--",
        "Fee Currency" => "",
        "Notes" => ""
      }
      result = CsvRowParser.parse_row(row, row_number: 2)
      assert_equal BigDecimal("1150.01"), result[:amount]
    end

    test "row_signature is deterministic for same inputs" do
      t = Time.utc(2026, 1, 14, 13, 5, 0)
      sig1 = CsvRowParser.row_signature(t, "AAVE", "buy", BigDecimal("174.52"), BigDecimal("2.292"))
      sig2 = CsvRowParser.row_signature(t, "AAVE", "buy", BigDecimal("174.52"), BigDecimal("2.292"))
      assert_equal sig1, sig2
    end

    test "row_signature differs for different amount" do
      t = Time.utc(2026, 1, 14, 13, 5, 0)
      sig1 = CsvRowParser.row_signature(t, "AAVE", "buy", BigDecimal("174.52"), BigDecimal("2.292"))
      sig2 = CsvRowParser.row_signature(t, "AAVE", "buy", BigDecimal("174.52"), BigDecimal("2.293"))
      assert_not_equal sig1, sig2
    end

    test "parse_row raises ParseError for blank token" do
      row = {
        "Date (UTC-3:00)" => "2026-01-14 10:05:00",
        "Token" => "  ",
        "Type" => "buy",
        "Price (USD)" => "1",
        "Amount" => "1",
        "Total value (USD)" => "1",
        "Fee" => "",
        "Fee Currency" => "",
        "Notes" => ""
      }
      err = assert_raises(CsvRowParser::ParseError) do
        CsvRowParser.parse_row(row, row_number: 2)
      end
      assert_includes err.message, "Token is blank"
    end

    test "parse_row raises ParseError for invalid type" do
      row = {
        "Date (UTC-3:00)" => "2026-01-14 10:05:00",
        "Token" => "BTC",
        "Type" => "swap",
        "Price (USD)" => "1",
        "Amount" => "1",
        "Total value (USD)" => "1",
        "Fee" => "",
        "Fee Currency" => "",
        "Notes" => ""
      }
      err = assert_raises(CsvRowParser::ParseError) do
        CsvRowParser.parse_row(row, row_number: 2)
      end
      assert_includes err.message, "Type must be buy or sell"
    end
  end
end
