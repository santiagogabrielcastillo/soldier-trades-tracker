# frozen_string_literal: true

require "test_helper"

class Admin::AdminsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @super_admin = users(:super_admin)
    @super_admin.update!(password: "password", password_confirmation: "password")

    @admin = users(:admin)
    @admin.update!(password: "password", password_confirmation: "password")

    @student = users(:one)
  end

  # ── Access ──────────────────────────────────────────────────────────────────

  test "admin can view admins index" do
    post login_url, params: { email: @admin.email, password: "password" }
    get admin_admins_url
    assert_response :success
  end

  test "super_admin can view admins index" do
    post login_url, params: { email: @super_admin.email, password: "password" }
    get admin_admins_url
    assert_response :success
  end

  test "student cannot access admins index" do
    @student.update!(password: "password", password_confirmation: "password")
    post login_url, params: { email: @student.email, password: "password" }
    get admin_admins_url
    assert_redirected_to root_url
  end

  # ── Show ────────────────────────────────────────────────────────────────────

  test "admin can view admin show page" do
    post login_url, params: { email: @admin.email, password: "password" }
    get admin_admin_url(@admin)
    assert_response :success
  end

  test "set_admin scopes to role=admin only" do
    post login_url, params: { email: @super_admin.email, password: "password" }
    get admin_admin_url(@student)
    assert_response :not_found
  end

  # ── toggle_active (super_admin only) ────────────────────────────────────────

  test "super_admin can toggle_active on an admin" do
    post login_url, params: { email: @super_admin.email, password: "password" }

    assert @admin.active?
    patch toggle_active_admin_admin_url(@admin)
    assert_redirected_to admin_admins_url
    assert_not @admin.reload.active?
  ensure
    @admin.update_columns(active: true)
  end

  test "admin cannot toggle_active on another admin" do
    second_admin = User.create!(email: "second@example.com", password: "password",
                                password_confirmation: "password", role: "admin", active: true)
    post login_url, params: { email: @admin.email, password: "password" }

    patch toggle_active_admin_admin_url(second_admin)
    assert_redirected_to root_url
    assert_match "Not authorized", flash[:alert]
  ensure
    second_admin.destroy
  end

  # ── demote (super_admin only) ────────────────────────────────────────────────

  test "super_admin can demote an admin to user" do
    post login_url, params: { email: @super_admin.email, password: "password" }

    patch demote_admin_admin_url(@admin)
    assert_redirected_to admin_admins_url
    assert_equal "user", @admin.reload.role
  ensure
    @admin.update_columns(role: "admin")
  end

  test "admin cannot demote another admin" do
    second_admin = User.create!(email: "second@example.com", password: "password",
                                password_confirmation: "password", role: "admin", active: true)
    post login_url, params: { email: @admin.email, password: "password" }

    patch demote_admin_admin_url(second_admin)
    assert_redirected_to root_url
    assert_match "Not authorized", flash[:alert]
  ensure
    second_admin.destroy
  end
end
