# frozen_string_literal: true

require "csv"

module Spot
  # Imports spot transactions from a CSV file. Uses content-based row signatures to skip
  # duplicates on re-upload. Wraps import in a transaction so partial failure rolls back.
  class ImportFromCsvService
    MAX_FILE_SIZE_BYTES = 10 * 1024 * 1024 # 10 MB
    MAX_ROWS = 2000

    Result = Struct.new(:created, :skipped, :errors, keyword_init: true)

    def self.call(spot_account:, csv_io:)
      new(spot_account: spot_account, csv_io: csv_io).call
    end

    def initialize(spot_account:, csv_io:)
      @spot_account = spot_account
      @csv_io = csv_io
    end

    def call
      validate_input!
      rows = read_csv_rows
      result = import_loop(rows)
      Result.new(created: result[:created], skipped: result[:skipped], errors: result[:errors])
    end

    private

    def validate_input!
      raise ArgumentError, "spot_account is required" unless @spot_account.present?
      raise ArgumentError, "csv_io is required" unless @csv_io.present?
      if @csv_io.respond_to?(:size) && @csv_io.size > MAX_FILE_SIZE_BYTES
        raise ArgumentError, "CSV file must be under #{MAX_FILE_SIZE_BYTES / 1_000_000} MB"
      end
    end

    def read_csv_rows
      content = @csv_io.respond_to?(:read) ? @csv_io.read : @csv_io.to_s
      content = content.dup.force_encoding(Encoding::UTF_8) if content.encoding != Encoding::UTF_8
      content = content.sub(/\A\xEF\xBB\xBF/, "") # strip BOM
      rows = CSV.parse(content, headers: true)
      if rows.size > MAX_ROWS
        raise ArgumentError, "CSV has #{rows.size} rows; maximum is #{MAX_ROWS}"
      end
      rows
    end

    def import_loop(rows)
      created = 0
      skipped = 0
      errors = []

      @spot_account.transaction do
        rows.each_with_index do |row, index|
          row_number = index + 2
          outcome = process_row(row, row_number)
          case outcome
          when :created then created += 1
          when :skipped then skipped += 1
          when String then errors << outcome
          end
        end
      end

      { created: created, skipped: skipped, errors: errors }
    end

    def process_row(row, row_number)
      attrs = Spot::CsvRowParser.parse_row(row, row_number: row_number)
      existing = @spot_account.spot_transactions.find_by(row_signature: attrs[:row_signature])
      if existing
        return :skipped
      end
      @spot_account.spot_transactions.create!(attrs)
      :created
    rescue Spot::CsvRowParser::ParseError => e
      e.message
    rescue ActiveRecord::RecordInvalid => e
      "Row #{row_number}: #{e.message}"
    rescue ActiveRecord::RecordNotUnique
      :skipped
    end
  end
end
