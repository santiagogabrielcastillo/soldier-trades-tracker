# frozen_string_literal: true

require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  test "format_money returns dash for nil" do
    assert_equal "—", format_money(nil)
  end

  test "format_money wraps real value in span with data-money" do
    result = format_money(1234.56)
    assert_includes result, "data-money"
    assert_includes result, "$1,234.56"
    assert_includes result, "font-numeric"
  end

  test "format_ars returns dash for nil" do
    assert_equal "—", format_ars(nil)
  end

  test "format_ars wraps real value in span with data-money" do
    result = format_ars(5000)
    assert_includes result, "data-money"
    assert_includes result, "font-numeric"
  end
end
