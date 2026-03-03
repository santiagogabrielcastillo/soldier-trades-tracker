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

  test "show redirects to login when not signed in" do
    get root_path
    assert_redirected_to login_path
  end

  private

  def sign_in_as(user)
    post login_path, params: { email: user.email, password: "password" }
    follow_redirect!
  end
end
