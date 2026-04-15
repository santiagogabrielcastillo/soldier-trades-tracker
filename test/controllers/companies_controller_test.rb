# frozen_string_literal: true

require "test_helper"

class CompaniesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @user.update!(password: "password", password_confirmation: "password")
    @company = companies(:apple)
  end

  test "index redirects to login when not signed in" do
    get companies_path
    assert_redirected_to login_path
  end

  test "index returns 200 when signed in" do
    sign_in_as(@user)
    get companies_path
    assert_response :success
    assert_select "h1", text: "Companies"
  end

  test "show returns 200 for own company" do
    sign_in_as(@user)
    get company_path(@company)
    assert_response :success
    assert_select "h1", text: /Apple Inc\./
  end

  test "show raises 404 for another user's company" do
    sign_in_as(@user)
    get company_path(companies(:other_user_company))
    assert_response :not_found
  end

  test "new returns 200" do
    sign_in_as(@user)
    get new_company_path
    assert_response :success
  end

  test "create saves company and redirects to show" do
    sign_in_as(@user)
    assert_difference "Company.count", 1 do
      post companies_path, params: { company: { ticker: "tsla", name: "Tesla Inc.", sector: "Automotive" } }
    end
    company = Company.find_by(ticker: "TSLA", user: @user)
    assert_redirected_to company_path(company)
    assert_equal "TSLA", company.ticker
  end

  test "create with invalid params renders new" do
    sign_in_as(@user)
    assert_no_difference "Company.count" do
      post companies_path, params: { company: { ticker: "", name: "" } }
    end
    assert_response :unprocessable_entity
  end

  test "edit returns 200 for own company" do
    sign_in_as(@user)
    get edit_company_path(@company)
    assert_response :success
  end

  test "update saves changes and redirects to show" do
    sign_in_as(@user)
    patch company_path(@company), params: { company: { name: "Apple Inc. Updated" } }
    assert_redirected_to company_path(@company)
    assert_equal "Apple Inc. Updated", @company.reload.name
  end

  test "update with invalid params renders edit" do
    sign_in_as(@user)
    patch company_path(@company), params: { company: { name: "" } }
    assert_response :unprocessable_entity
  end

  test "destroy deletes company and redirects to index" do
    sign_in_as(@user)
    assert_difference "Company.count", -1 do
      delete company_path(@company)
    end
    assert_redirected_to companies_path
  end

  test "cannot edit another user's company" do
    sign_in_as(@user)
    get edit_company_path(companies(:other_user_company))
    assert_response :not_found
  end

  test "comparison returns 200 for own company" do
    sign_in_as(@user)
    get comparison_company_path(@company)
    assert_response :success
    assert_select "h1", text: /Apple Inc\./
  end

  test "comparison shows standard metric rows" do
    sign_in_as(@user)
    get comparison_company_path(@company)
    assert_response :success
    assert_select "td", text: "Revenue"
    assert_select "td", text: "Net Income"
    assert_select "td", text: "EPS"
  end

  test "comparison shows custom metric definition rows" do
    sign_in_as(@user)
    get comparison_company_path(@company)
    assert_response :success
    assert_select "td", text: /Services Revenue/
  end

  test "comparison shows period labels as column headers" do
    sign_in_as(@user)
    get comparison_company_path(@company)
    assert_response :success
    assert_select "th", text: "Q4 2024"
    assert_select "th", text: "FY2024"
  end

  test "comparison raises 404 for another user's company" do
    sign_in_as(@user)
    get comparison_company_path(companies(:other_user_company))
    assert_response :not_found
  end

  private

  def sign_in_as(user)
    post login_path, params: { email: user.email, password: "password" }
    follow_redirect!
  end
end
