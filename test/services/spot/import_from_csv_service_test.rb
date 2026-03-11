# frozen_string_literal: true

require "test_helper"

module Spot
  class ImportFromCsvServiceTest < ActiveSupport::TestCase
    setup do
      @spot_account = spot_accounts(:one)
      @spot_account.spot_transactions.destroy_all
    end

    test "imports rows and skips duplicates on re-upload" do
      csv = <<~CSV
        Date (UTC-3:00),Token,Type,Price (USD),Amount,Total value (USD),Fee,Fee Currency,Notes
        2026-01-14 10:05:00,AAVE,buy,174.52,2.292,400.00,--,,
        2026-01-14 10:00:00,WLD,buy,0.606,330,199.98,--,,
      CSV
      result = ImportFromCsvService.call(spot_account: @spot_account, csv_io: StringIO.new(csv))
      assert_equal 2, result.created
      assert_equal 0, result.skipped
      assert_empty result.errors

      # Re-upload same CSV
      result2 = ImportFromCsvService.call(spot_account: @spot_account, csv_io: StringIO.new(csv))
      assert_equal 0, result2.created
      assert_equal 2, result2.skipped
      assert_empty result2.errors
      assert_equal 2, @spot_account.spot_transactions.count
    end

    test "returns errors for invalid rows" do
      csv = <<~CSV
        Date (UTC-3:00),Token,Type,Price (USD),Amount,Total value (USD),Fee,Fee Currency,Notes
        2026-01-14 10:05:00,,buy,174.52,2.292,400,--,,
      CSV
      result = ImportFromCsvService.call(spot_account: @spot_account, csv_io: StringIO.new(csv))
      assert_equal 0, result.created
      assert_equal 0, result.skipped
      assert_equal 1, result.errors.size
      assert_includes result.errors.first, "Token is blank"
    end

    test "raises when csv_io is missing" do
      assert_raises(ArgumentError, match: "csv_io is required") do
        ImportFromCsvService.call(spot_account: @spot_account, csv_io: nil)
      end
    end

    test "raises when spot_account is missing" do
      assert_raises(ArgumentError, match: "spot_account is required") do
        ImportFromCsvService.call(spot_account: nil, csv_io: StringIO.new("a,b\n1,2"))
      end
    end
  end
end
