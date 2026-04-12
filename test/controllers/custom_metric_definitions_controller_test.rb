# frozen_string_literal: true

require "test_helper"

class CustomMetricDefinitionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @user.update!(password: "password", password_confirmation: "password")
    @company = companies(:apple)
  end

  test "create redirects to login when not signed in" do
    post company_custom_metric_definitions_path(@company), params: { name: "ARR", data_type: "number" }
    assert_redirected_to login_path
  end

  test "create adds definition and redirects to company show" do
    sign_in_as(@user)
    assert_difference "CustomMetricDefinition.count", 1 do
      post company_custom_metric_definitions_path(@company),
           params: { name: "Active Users", data_type: "number" }
    end
    assert_redirected_to company_path(@company)
    assert CustomMetricDefinition.exists?(company: @company, name: "Active Users", data_type: "number")
  end

  test "create with invalid params redirects to company show with alert" do
    sign_in_as(@user)
    assert_no_difference "CustomMetricDefinition.count" do
      post company_custom_metric_definitions_path(@company),
           params: { name: "", data_type: "number" }
    end
    assert_redirected_to company_path(@company)
    assert_match /can't be blank/i, flash[:alert].to_s
  end

  test "create raises 404 for another user's company" do
    sign_in_as(@user)
    post company_custom_metric_definitions_path(companies(:other_user_company)),
         params: { name: "ARR", data_type: "number" }
    assert_response :not_found
  end

  test "destroy removes definition and redirects to company show" do
    sign_in_as(@user)
    defn = custom_metric_definitions(:apple_services)
    assert_difference "CustomMetricDefinition.count", -1 do
      delete company_custom_metric_definition_path(@company, defn)
    end
    assert_redirected_to company_path(@company)
  end

  test "destroy cascades to custom_metric_values" do
    sign_in_as(@user)
    defn = custom_metric_definitions(:apple_services)
    value_count_before = defn.custom_metric_values.count
    assert value_count_before > 0, "Fixture should have at least one value"
    assert_difference "CustomMetricValue.count", -value_count_before do
      delete company_custom_metric_definition_path(@company, defn)
    end
  end

  private

  def sign_in_as(user)
    post login_path, params: { email: user.email, password: "password" }
    follow_redirect!
  end
end
