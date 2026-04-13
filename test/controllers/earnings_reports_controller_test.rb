# frozen_string_literal: true

require "test_helper"

class EarningsReportsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @user.update!(password: "password", password_confirmation: "password")
    @company = companies(:apple)
    @report  = earnings_reports(:apple_q4_2024)
  end

  test "new redirects to login when not signed in" do
    get new_company_earnings_report_path(@company)
    assert_redirected_to login_path
  end

  test "new returns 200 for own company" do
    sign_in_as(@user)
    get new_company_earnings_report_path(@company)
    assert_response :success
  end

  test "new raises 404 for another user's company" do
    sign_in_as(@user)
    get new_company_earnings_report_path(companies(:other_user_company))
    assert_response :not_found
  end

  test "create saves report and redirects to show" do
    sign_in_as(@user)
    assert_difference "EarningsReport.count", 1 do
      post company_earnings_reports_path(@company), params: {
        earnings_report: {
          period_type: "annual",
          fiscal_year: 2023,
          revenue: 383285000000,
          net_income: 96995000000,
          eps: 6.13
        }
      }
    end
    report = EarningsReport.find_by(company: @company, fiscal_year: 2023, period_type: "annual")
    assert_redirected_to company_earnings_report_path(@company, report)
  end

  test "create with invalid params renders new" do
    sign_in_as(@user)
    assert_no_difference "EarningsReport.count" do
      post company_earnings_reports_path(@company), params: {
        earnings_report: { period_type: "quarterly", fiscal_year: 2024, fiscal_quarter: nil }
      }
    end
    assert_response :unprocessable_entity
  end

  test "show returns 200 for own company's report" do
    sign_in_as(@user)
    get company_earnings_report_path(@company, @report)
    assert_response :success
    assert_select "h1", text: /Q4 2024/
  end

  test "show raises 404 for another user's company" do
    sign_in_as(@user)
    other_company = companies(:other_user_company)
    other_report  = other_company.earnings_reports.create!(period_type: "annual", fiscal_year: 2024)
    get company_earnings_report_path(other_company, other_report)
    assert_response :not_found
  end

  test "edit returns 200 for own report" do
    sign_in_as(@user)
    get edit_company_earnings_report_path(@company, @report)
    assert_response :success
  end

  test "update saves changes and redirects to show" do
    sign_in_as(@user)
    patch company_earnings_report_path(@company, @report), params: {
      earnings_report: { notes: "Beat expectations" }
    }
    assert_redirected_to company_earnings_report_path(@company, @report)
    assert_equal "Beat expectations", @report.reload.notes
  end

  test "update with invalid params renders edit" do
    sign_in_as(@user)
    patch company_earnings_report_path(@company, @report), params: {
      earnings_report: { period_type: "quarterly", fiscal_quarter: nil }
    }
    assert_response :unprocessable_entity
  end

  test "destroy removes report and redirects to company" do
    sign_in_as(@user)
    assert_difference "EarningsReport.count", -1 do
      delete company_earnings_report_path(@company, @report)
    end
    assert_redirected_to company_path(@company)
  end

  private

  def sign_in_as(user)
    post login_path, params: { email: user.email, password: "password" }
    follow_redirect!
  end
end
