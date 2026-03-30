# frozen_string_literal: true

require "csv"
require "date"

module Exchanges
  module Binance
    # Parses a Binance Futures Trade History CSV export into an array of trade hashes
    # compatible with ExchangeAccounts::CsvImportService.
    #
    # Expected headers: Uid, Time, Symbol, Side, Price, Quantity, Amount, Fee,
    #                   Realized Profit, Buyer, Maker, Trade ID, Order ID
    #
    # Time column format: "YY-MM-DD HH:MM:SS" — only the date part is stored (midnight UTC).
    # Fee column format: "0.295 USDC" — numeric portion extracted, currency discarded.
    # positionSide defaults to "BOTH" (one-way mode) since the CSV has no position side column.
    class CsvParser
      REQUIRED_HEADERS = ["Trade ID", "Time", "Symbol", "Side", "Price", "Quantity", "Fee"].freeze

      ParseError = Class.new(StandardError)

      def self.call(csv_io)
        new(csv_io).call
      end

      def initialize(csv_io)
        @csv_io = csv_io
      end

      def call
        content = read_content
        rows = CSV.parse(content, headers: true)
        validate_headers!(rows.headers)
        rows.filter_map { |row| parse_row(row) }
      end

      private

      def read_content
        raw = @csv_io.respond_to?(:read) ? @csv_io.read : @csv_io.to_s
        raw = raw.dup.force_encoding(Encoding::UTF_8) if raw.encoding != Encoding::UTF_8
        raw.sub(/\A\xEF\xBB\xBF/, "") # strip BOM
      end

      def validate_headers!(headers)
        missing = REQUIRED_HEADERS - Array(headers)
        return if missing.empty?
        raise ParseError, "Missing required columns: #{missing.join(', ')}. " \
                          "Expected a Binance Futures Trade History CSV."
      end

      def parse_row(row)
        trade_id = row["Trade ID"]&.to_s&.strip
        return nil if trade_id.blank?

        executed_at = parse_date(row["Time"])
        return nil if executed_at.nil?

        symbol_raw = row["Symbol"]&.to_s&.strip
        return nil if symbol_raw.blank?

        side = row["Side"]&.to_s&.strip&.downcase
        return nil unless %w[buy sell].include?(side)

        symbol = Binance::TradeNormalizer.normalize_symbol(symbol_raw)
        return nil if symbol.blank?

        {
          exchange_reference_id: trade_id,
          symbol:                symbol,
          side:                  side,
          price:                 row["Price"].to_d,
          quantity:              row["Quantity"].to_d,
          fee_from_exchange:     parse_fee(row["Fee"]),
          executed_at:           executed_at,
          raw_payload:           row.to_h.merge(
            "positionSide" => "BOTH",
            "realizedPnl"  => row["Realized Profit"].to_s.strip
          )
        }
      end

      # "YY-MM-DD HH:MM:SS" → store only the date as midnight UTC
      def parse_date(str)
        return nil if str.blank?
        d = Date.strptime(str.to_s.strip[0, 8], "%y-%m-%d")
        Time.utc(d.year, d.month, d.day)
      rescue Date::Error, ArgumentError
        nil
      end

      # "0.29528919 USDC" → BigDecimal("0.29528919")
      def parse_fee(str)
        return BigDecimal("0") if str.blank?
        str.to_s.strip.split(" ").first.to_d
      end
    end
  end
end
