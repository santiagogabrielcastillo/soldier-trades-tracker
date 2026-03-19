# frozen_string_literal: true

require "test_helper"

class StockPortfolioTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
  end

  test "valid with us market" do
    portfolio = @user.stock_portfolios.build(name: "US", market: "us")
    assert portfolio.valid?
  end

  test "valid with argentina market" do
    portfolio = @user.stock_portfolios.build(name: "ARG", market: "argentina")
    assert portfolio.valid?
  end

  test "invalid with unknown market" do
    portfolio = @user.stock_portfolios.build(name: "Bad", market: "brazil")
    assert_not portfolio.valid?
    assert_includes portfolio.errors[:market], "is not included in the list"
  end

  test "defaults to us market" do
    portfolio = @user.stock_portfolios.create!(name: "Default")
    assert_equal "us", portfolio.market
  end

  test "argentina? returns true for argentina market" do
    portfolio = @user.stock_portfolios.build(name: "ARG", market: "argentina")
    assert portfolio.argentina?
  end

  test "argentina? returns false for us market" do
    portfolio = @user.stock_portfolios.build(name: "US", market: "us")
    assert_not portfolio.argentina?
  end

  test "market cannot be changed after trades exist" do
    portfolio = @user.stock_portfolios.create!(name: "US", market: "us", default: false)
    portfolio.stock_trades.create!(
      ticker: "AAPL",
      side: "buy",
      price_usd: BigDecimal("100"),
      shares: BigDecimal("5"),
      total_value_usd: BigDecimal("500"),
      executed_at: 1.day.ago,
      row_signature: Digest::SHA256.hexdigest("test-sig-1")
    )
    portfolio.market = "argentina"
    assert_not portfolio.valid?
    assert_includes portfolio.errors[:market], "cannot be changed after trades have been recorded"
  end

  test "market can be changed on empty portfolio" do
    portfolio = @user.stock_portfolios.create!(name: "Empty", market: "us", default: false)
    portfolio.market = "argentina"
    assert portfolio.valid?
  end
end
