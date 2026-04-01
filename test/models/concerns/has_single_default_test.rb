# test/models/concerns/has_single_default_test.rb
require "test_helper"

class HasSingleDefaultTest < ActiveSupport::TestCase
  # Use Portfolio as the test subject since it includes the concern
  setup do
    @user = users(:one)
    @user.portfolios.delete_all
  end

  test "saving a portfolio as default clears other defaults for the same user" do
    p1 = @user.portfolios.create!(name: "P1", start_date: Date.today, default: true)
    p2 = @user.portfolios.create!(name: "P2", start_date: Date.today, default: false)

    p2.update!(default: true)

    assert_equal false, p1.reload.default
    assert_equal true, p2.reload.default
  end

  test "non-default save does not clear other defaults" do
    p1 = @user.portfolios.create!(name: "P1", start_date: Date.today, default: true)
    p2 = @user.portfolios.create!(name: "P2", start_date: Date.today, default: false)

    p2.update!(name: "P2 updated")

    assert_equal true, p1.reload.default
  end
end
