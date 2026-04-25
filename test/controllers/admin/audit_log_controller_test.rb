require "test_helper"

class Admin::AuditLogControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:admin)
    @admin.update!(password: "password", password_confirmation: "password")
    post login_url, params: { email: @admin.email, password: "password" }
  end

  test "show renders audit log" do
    get admin_audit_log_url
    assert_response :success
  end

  test "show filters by student" do
    get admin_audit_log_url, params: { student_id: users(:one).id }
    assert_response :success
  end

  test "show filters by event type" do
    get admin_audit_log_url, params: { event: "update" }
    assert_response :success
  end

  test "non-admin is redirected" do
    student = users(:one)
    student.update!(password: "password", password_confirmation: "password")
    post login_url, params: { email: student.email, password: "password" }
    get admin_audit_log_url
    assert_redirected_to root_path
  end
end
