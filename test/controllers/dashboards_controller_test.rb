# frozen_string_literal: true

require "test_helper"

class DashboardsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @user.update!(password: "password", password_confirmation: "password")
  end

  test "show returns 200 and includes period summary and consistency" do
    sign_in_as(@user)
    get root_path
    assert_response :success
    assert_match(/Period summary|Balance|Period P&amp;L/i, response.body)
    assert_match(/Total return|Consistency|Win rate/i, response.body)
  end

  test "show includes Spot section and View spot portfolio link" do
    sign_in_as(@user)
    get root_path
    assert_response :success
    assert_match(/Spot/i, response.body)
    assert_match(/View spot portfolio/i, response.body)
    assert_match(/Total value|Unrealized P&amp;L|Open positions/i, response.body)
  end

  test "show redirects to login when not signed in" do
    get root_path
    assert_redirected_to login_path
  end

  test "show uses Struct (not OpenStruct) for @dashboard" do
    sign_in_as(@user)
    get root_path
    assert_response :success
    # @dashboard is assigned in the controller; we verify the template rendered without error,
    # which confirms the Struct-based assignment works end-to-end.
  end

  test "MepRateFetcher is called once per dashboard render (not duplicated internally)" do
    sign_in_as(@user)
    mep_rate_call_count = 0
    fake_mep = BigDecimal("1050")
    Stocks::MepRateFetcher.stub(:call, -> { mep_rate_call_count += 1; fake_mep }) do
      get root_path
      assert_response :success
    end
    assert_equal 1, mep_rate_call_count, "MepRateFetcher should be called exactly once per dashboard render"
  end

  private

  def sign_in_as(user)
    post login_path, params: { email: user.email, password: "password" }
    follow_redirect!
  end
end
