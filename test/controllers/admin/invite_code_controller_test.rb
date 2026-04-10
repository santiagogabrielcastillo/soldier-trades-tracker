# frozen_string_literal: true

require "test_helper"

class Admin::InviteCodeControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:admin)
    @admin.update!(password: "password", password_confirmation: "password")
    post login_url, params: { email: @admin.email, password: "password" }

    InviteCode.delete_all
  end

  teardown do
    InviteCode.delete_all
  end

  test "show renders current invite code" do
    InviteCode.create!(code: "showtest1234567890abcdefghijk", expires_at: 1.day.from_now)
    get admin_invite_code_url
    assert_response :success
  end

  test "show renders with no code" do
    get admin_invite_code_url
    assert_response :success
  end

  test "create rotates the invite code" do
    future = 7.days.from_now.strftime("%Y-%m-%dT%H:%M")
    post admin_invite_code_url, params: { expires_at: future }
    assert_redirected_to admin_invite_code_url
    assert_equal 1, InviteCode.count
    assert InviteCode.first.expires_at > Time.current
  end

  test "create rejects blank expiry" do
    post admin_invite_code_url, params: { expires_at: "" }
    assert_redirected_to admin_invite_code_url
    assert_match "valid future expiry", flash[:alert]
    assert_equal 0, InviteCode.count
  end

  test "create rejects past expiry" do
    past = 1.day.ago.strftime("%Y-%m-%dT%H:%M")
    post admin_invite_code_url, params: { expires_at: past }
    assert_redirected_to admin_invite_code_url
    assert_match "valid future expiry", flash[:alert]
  end
end
