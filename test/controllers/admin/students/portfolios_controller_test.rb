require "test_helper"

class Admin::Students::PortfoliosControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:admin)
    @admin.update!(password: "password", password_confirmation: "password")
    post login_url, params: { email: @admin.email, password: "password" }
    @student   = users(:one)
    @portfolio = portfolios(:one)
  end

  test "index lists portfolios" do
    get admin_student_portfolios_url(@student)
    assert_response :success
  end

  test "create adds portfolio" do
    assert_difference "Portfolio.unscoped.where(user: @student).count", 1 do
      post admin_student_portfolios_url(@student), params: {
        portfolio: { name: "Admin Created", start_date: "2026-01-01" }
      }
    end
    assert_redirected_to admin_student_path(@student)
  end

  test "update modifies portfolio" do
    patch admin_student_portfolio_url(@student, @portfolio), params: {
      portfolio: { name: "Renamed", start_date: @portfolio.start_date }
    }
    assert_redirected_to admin_student_path(@student)
    assert_equal "Renamed", @portfolio.reload.name
  end

  test "destroy soft-deletes portfolio" do
    delete admin_student_portfolio_url(@student, @portfolio)
    assert_not_nil @portfolio.reload.discarded_at
  end
end
