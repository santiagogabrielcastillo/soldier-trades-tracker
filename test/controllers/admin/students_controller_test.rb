# frozen_string_literal: true

require "test_helper"

class Admin::StudentsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:admin)
    @admin.update!(password: "password", password_confirmation: "password")
    post login_url, params: { email: @admin.email, password: "password" }

    @student = users(:one)
  end

  test "index lists non-admin students" do
    get admin_students_url
    assert_response :success
  end

  test "show renders student detail" do
    get admin_student_url(@student)
    assert_response :success
  end

  test "toggle_active deactivates an active student" do
    assert @student.active?
    patch toggle_active_admin_student_url(@student)
    assert_redirected_to admin_students_url
    assert_not @student.reload.active?
  ensure
    @student.update_columns(active: true)
  end

  test "toggle_active activates an inactive student" do
    @student.update_columns(active: false)
    patch toggle_active_admin_student_url(@student)
    assert_redirected_to admin_students_url
    assert @student.reload.active?
  end

  test "set_student scopes to non-admins only" do
    # Admin user cannot be accessed via the students endpoint (scoped to admin: false)
    get admin_student_url(@admin)
    assert_response :not_found
  end
end
