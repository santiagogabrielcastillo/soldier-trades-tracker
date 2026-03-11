# frozen_string_literal: true

require "digest"

module Spot
  # Parses a single row from the spot transaction CSV and computes a content-based row signature.
  # CSV columns: Date (UTC-3:00), Token, Type, Price (USD), Amount, Total value (USD), Fee, Fee Currency, Notes.
  # MVP: Fee and Fee Currency are ignored.
  class CsvRowParser
    EXPECTED_HEADERS = [
      "Date (UTC-3:00)",
      "Token",
      "Type",
      "Price (USD)",
      "Amount",
      "Total value (USD)",
      "Fee",
      "Fee Currency",
      "Notes"
    ].freeze

    class ParseError < StandardError; end

    # CSV is in UTC-3 (e.g. Buenos Aires). We parse and store in UTC.
    CSV_TIMEZONE = ActiveSupport::TimeZone[-3] # UTC-3

    def self.parse_row(row, row_number: nil)
      new.parse_row(row, row_number: row_number)
    end

    def self.row_signature(executed_at, token, side, price_usd, amount)
      new.row_signature(executed_at, token, side, price_usd, amount)
    end

    def parse_row(row, row_number: nil)
      raise ArgumentError, "row must be a Hash or CSV::Row" unless row.respond_to?(:[])

      executed_at = parse_date(row["Date (UTC-3:00)"], row_number)
      token = normalize_token(row["Token"], row_number)
      side = normalize_side(row["Type"], row_number)
      price_usd = parse_decimal(row["Price (USD)"], "Price (USD)", row_number)
      amount = parse_decimal(row["Amount"], "Amount", row_number)
      total_value_usd = parse_decimal(row["Total value (USD)"], "Total value (USD)", row_number)
      notes = row["Notes"].to_s.strip.presence

      sig = row_signature(executed_at, token, side, price_usd, amount)

      {
        executed_at: executed_at,
        token: token,
        side: side,
        price_usd: price_usd,
        amount: amount,
        total_value_usd: total_value_usd,
        notes: notes,
        row_signature: sig
      }
    rescue ParseError
      raise
    rescue StandardError => e
      raise ParseError, "Row #{row_number}: #{e.message}"
    end

    def row_signature(executed_at, token, side, price_usd, amount)
      # Canonical string: same logical row always produces same signature.
      # Decimals normalized to avoid "0.5454" vs "0.54540" differences.
      iso = executed_at.respond_to?(:iso8601) ? executed_at.iso8601(3) : executed_at.to_s
      token_s = token.to_s.strip.upcase
      side_s = side.to_s.strip.downcase
      price_s = bigdecimal_to_canonical(price_usd)
      amount_s = bigdecimal_to_canonical(amount)
      canonical = [iso, token_s, side_s, price_s, amount_s].join("|")
      Digest::SHA256.hexdigest(canonical)
    end

    private

    def parse_date(value, row_number)
      raw = value.to_s.strip
      raise ParseError, "Row #{row_number}: Date (UTC-3:00) is blank" if raw.blank?
      time = CSV_TIMEZONE.parse(raw)
      raise ParseError, "Row #{row_number}: Date (UTC-3:00) could not be parsed: #{raw}" if time.nil?
      time.utc
    end

    def normalize_token(value, row_number)
      token = value.to_s.strip.upcase
      raise ParseError, "Row #{row_number}: Token is blank" if token.blank?
      token
    end

    def normalize_side(value, row_number)
      side = value.to_s.strip.downcase
      raise ParseError, "Row #{row_number}: Type must be buy or sell, got: #{value.inspect}" unless %w[buy sell].include?(side)
      side
    end

    def parse_decimal(value, field_name, row_number)
      raw = value.to_s.strip.gsub(",", "")
      raise ParseError, "Row #{row_number}: #{field_name} is blank" if raw.blank?
      BigDecimal(raw)
    rescue ArgumentError, TypeError
      raise ParseError, "Row #{row_number}: #{field_name} is not a valid number: #{value.inspect}"
    end

    def bigdecimal_to_canonical(val)
      return val.to_s if val.is_a?(String)
      return val.to_s("F") if val.is_a?(BigDecimal)
      val.to_s
    end
  end
end
