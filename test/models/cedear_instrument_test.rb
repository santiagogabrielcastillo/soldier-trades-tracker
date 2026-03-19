# frozen_string_literal: true

require "test_helper"

class CedearInstrumentTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
  end

  test "valid instrument" do
    instrument = @user.cedear_instruments.build(ticker: "GOOG", ratio: 25.0)
    assert instrument.valid?
  end

  test "requires ticker" do
    instrument = @user.cedear_instruments.build(ratio: 10.0)
    assert_not instrument.valid?
    assert_includes instrument.errors[:ticker], "can't be blank"
  end

  test "requires ratio" do
    instrument = @user.cedear_instruments.build(ticker: "GOOG")
    assert_not instrument.valid?
    assert_includes instrument.errors[:ratio], "can't be blank"
  end

  test "ratio must be greater than zero" do
    instrument = @user.cedear_instruments.build(ticker: "GOOG", ratio: 0)
    assert_not instrument.valid?
    assert_includes instrument.errors[:ratio], "must be greater than 0"
  end

  test "ticker is unique per user" do
    # :aapl fixture already exists for users(:one)
    instrument = @user.cedear_instruments.build(ticker: "AAPL", ratio: 10.0)
    assert_not instrument.valid?
    assert_includes instrument.errors[:ticker], "has already been taken"
  end

  test "same ticker allowed for different users" do
    other_user = users(:two)
    instrument = other_user.cedear_instruments.build(ticker: "AAPL", ratio: 10.0)
    assert instrument.valid?
  end

  test "ticker is upcased before save" do
    instrument = @user.cedear_instruments.create!(ticker: "goog", ratio: 25.0)
    assert_equal "GOOG", instrument.ticker
  end

  test "underlying_ticker is upcased before save" do
    instrument = @user.cedear_instruments.create!(ticker: "GOOG", ratio: 25.0, underlying_ticker: "googl")
    assert_equal "GOOGL", instrument.underlying_ticker
  end
end
