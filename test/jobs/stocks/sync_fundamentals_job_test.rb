# frozen_string_literal: true

require "test_helper"

module Stocks
  class SyncFundamentalsJobTest < ActiveSupport::TestCase
    test "upserts fundamentals including sector, industry, ev_ebitda" do
      fundamentals_data = {
        "MSFT" => Stocks::FundamentalsFetcher::FundamentalsData.new(
          pe: BigDecimal("35.2"), fwd_pe: BigDecimal("30.1"),
          peg: BigDecimal("2.10"), ps: BigDecimal("12.5"),
          pfcf: BigDecimal("40.0"), net_margin: BigDecimal("36.0"),
          roe: BigDecimal("40.0"), roic: BigDecimal("25.0"),
          debt_eq: BigDecimal("0.50"), sales_5y: BigDecimal("15.0"),
          sales_qq: BigDecimal("17.0"),
          sector: "Technology", industry: "Software-Infrastructure",
          ev_ebitda: BigDecimal("25.0")
        )
      }

      Stocks::FundamentalsFetcher.stub(:call, fundamentals_data) do
        Stocks::SyncFundamentalsJob.new.perform(["MSFT"])
      end

      record = StockFundamental.find_by!(ticker: "MSFT")
      assert_equal "Technology",              record.sector
      assert_equal "Software-Infrastructure", record.industry
      assert_in_delta 25.0, record.ev_ebitda.to_f, 0.01
      assert_in_delta 35.2, record.pe.to_f,         0.01
    end

    test "logs count of synced tickers" do
      Stocks::FundamentalsFetcher.stub(:call, {}) do
        assert_nothing_raised { Stocks::SyncFundamentalsJob.new.perform(["AAPL"]) }
      end
    end
  end
end
