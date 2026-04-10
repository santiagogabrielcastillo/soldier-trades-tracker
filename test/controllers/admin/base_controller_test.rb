# frozen_string_literal: true

require "test_helper"

# Tests the admin authorization gate shared by all Admin:: controllers.
# Uses Admin::DashboardController as a representative admin endpoint.
class Admin::BaseControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:admin)
    @admin.update!(password: "password", password_confirmation: "password")
    @student = users(:one)
    @student.update!(password: "password", password_confirmation: "password")
  end

  test "admin can access admin dashboard" do
    post login_url, params: { email: @admin.email, password: "password" }
    get admin_root_url
    assert_response :success
  end

  test "non-admin student is redirected from admin routes" do
    post login_url, params: { email: @student.email, password: "password" }
    get admin_root_url
    assert_redirected_to root_url
    assert_match "Not authorized", flash[:alert]
  end

  test "unauthenticated user is redirected to login from admin routes" do
    get admin_root_url
    assert_redirected_to login_url
  end

  test "inactive admin cannot access admin routes" do
    @admin.update_columns(active: false)
    post login_url, params: { email: @admin.email, password: "password" }

    # After login attempt, current_user is nil (inactive) so they get sent to login
    get admin_root_url
    assert_redirected_to login_url
  ensure
    @admin.update_columns(active: true)
  end
end
