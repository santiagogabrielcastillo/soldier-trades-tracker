# frozen_string_literal: true

require "test_helper"

class StockAnalysisTest < ActiveSupport::TestCase
  test "for_user_and_tickers returns hash indexed by ticker" do
    user = users(:one)
    result = StockAnalysis.for_user_and_tickers(user, ["AAPL", "MSFT"])

    assert_equal "buy",  result["AAPL"].rating
    assert_equal "hold", result["MSFT"].rating
  end

  test "for_user_and_tickers returns empty hash when no records" do
    user = users(:one)
    result = StockAnalysis.for_user_and_tickers(user, ["UNKNOWN"])

    assert_equal({}, result)
  end

  test "for_user_and_tickers ignores other users analyses" do
    user = users(:two)
    result = StockAnalysis.for_user_and_tickers(user, ["AAPL"])

    assert_empty result
  end

  test "validates presence of ticker, rating, analyzed_at" do
    analysis = StockAnalysis.new(user: users(:one))
    analysis.valid?

    assert_includes analysis.errors[:ticker],      "can't be blank"
    assert_includes analysis.errors[:rating],      "can't be blank"
    assert_includes analysis.errors[:analyzed_at], "can't be blank"
  end
end
