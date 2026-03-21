# frozen_string_literal: true

require "test_helper"

class StockPortfolioSnapshotTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @portfolio = @user.stock_portfolios.create!(name: "Snapshot Test", market: "argentina", default: false)
  end

  # --- validations ---

  test "valid with all required attributes" do
    snapshot = build_snapshot(total_value: "100000", cash_flow: "0")
    assert snapshot.valid?
  end

  test "invalid without total_value" do
    snapshot = build_snapshot(total_value: nil, cash_flow: "0")
    assert_not snapshot.valid?
    assert_includes snapshot.errors[:total_value], "can't be blank"
  end

  test "invalid when total_value is negative" do
    snapshot = build_snapshot(total_value: "-1", cash_flow: "0")
    assert_not snapshot.valid?
  end

  test "valid when total_value is zero" do
    snapshot = build_snapshot(total_value: "0", cash_flow: "0")
    assert snapshot.valid?
  end

  test "invalid without cash_flow" do
    snapshot = build_snapshot(total_value: "100", cash_flow: nil)
    assert_not snapshot.valid?
    assert_includes snapshot.errors[:cash_flow], "can't be blank"
  end

  test "invalid without recorded_at" do
    snapshot = @portfolio.stock_portfolio_snapshots.new(
      total_value: BigDecimal("100"),
      cash_flow: BigDecimal("0"),
      source: "manual"
    )
    assert_not snapshot.valid?
    assert_includes snapshot.errors[:recorded_at], "can't be blank"
  end

  test "invalid with unknown source" do
    snapshot = build_snapshot(total_value: "100", cash_flow: "0", source: "unknown")
    assert_not snapshot.valid?
    assert_includes snapshot.errors[:source], "is not included in the list"
  end

  test "valid with each accepted source" do
    %w[weekly monthly manual].each do |src|
      snapshot = build_snapshot(total_value: "100", cash_flow: "0", source: src)
      assert snapshot.valid?, "Expected source '#{src}' to be valid"
    end
  end

  # --- helper methods ---

  test "deposit? returns true when cash_flow is positive" do
    snapshot = build_snapshot(total_value: "100", cash_flow: "5000")
    assert snapshot.deposit?
    assert_not snapshot.withdrawal?
    assert_not snapshot.snapshot_only?
  end

  test "withdrawal? returns true when cash_flow is negative" do
    snapshot = build_snapshot(total_value: "100", cash_flow: "-3000")
    assert snapshot.withdrawal?
    assert_not snapshot.deposit?
    assert_not snapshot.snapshot_only?
  end

  test "snapshot_only? returns true when cash_flow is zero" do
    snapshot = build_snapshot(total_value: "100", cash_flow: "0")
    assert snapshot.snapshot_only?
    assert_not snapshot.deposit?
    assert_not snapshot.withdrawal?
  end

  # --- ordered scope ---

  test "ordered scope returns snapshots by recorded_at ascending" do
    s1 = build_snapshot(total_value: "100", cash_flow: "0", recorded_at: 2.weeks.ago).tap(&:save!)
    s2 = build_snapshot(total_value: "200", cash_flow: "0", recorded_at: 1.week.ago).tap(&:save!)
    s3 = build_snapshot(total_value: "300", cash_flow: "0", recorded_at: Time.current).tap(&:save!)

    ordered = @portfolio.stock_portfolio_snapshots.ordered
    assert_equal [ s1.id, s2.id, s3.id ], ordered.map(&:id)
  end

  private

  def build_snapshot(total_value:, cash_flow:, source: "manual", recorded_at: Time.current)
    @portfolio.stock_portfolio_snapshots.new(
      total_value: total_value ? BigDecimal(total_value.to_s) : nil,
      cash_flow: cash_flow ? BigDecimal(cash_flow.to_s) : nil,
      recorded_at: recorded_at,
      source: source
    )
  end
end
