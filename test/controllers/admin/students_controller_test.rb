# frozen_string_literal: true

require "test_helper"

class Admin::StudentsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:admin)
    @admin.update!(password: "password", password_confirmation: "password")
    post login_url, params: { email: @admin.email, password: "password" }

    @student = users(:one)
  end

  test "index lists role=user students" do
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

  test "set_student scopes to role=user only" do
    get admin_student_url(users(:admin))
    assert_response :not_found
  end

  test "promote sets student role to admin" do
    patch promote_admin_student_url(@student)
    assert_redirected_to admin_students_url
    assert_equal "admin", @student.reload.role
  ensure
    @student.update_columns(role: "user")
  end

  test "super_admin can also promote students" do
    super_admin = users(:super_admin)
    super_admin.update!(password: "password", password_confirmation: "password")
    post login_url, params: { email: super_admin.email, password: "password" }

    other_student = users(:two)
    patch promote_admin_student_url(other_student)
    assert_redirected_to admin_students_url
    assert_equal "admin", other_student.reload.role
  ensure
    users(:two).update_columns(role: "user")
  end
end
