# frozen_string_literal: true

require "test_helper"

class StocksControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @user.update!(password: "password", password_confirmation: "password")
  end

  # --- analyze_ticker ---

  test "analyze_ticker redirects to login when not authenticated" do
    post stocks_analyze_ticker_path("AAPL")
    assert_redirected_to login_path
  end

  test "analyze_ticker enqueues job for valid open-position ticker" do
    sign_in_as(@user)

    # Stub allowed tickers so we don't need real positions/watchlist data
    StocksController.any_instance.stub(:allowed_analysis_tickers, ["AAPL"]) do
      assert_enqueued_with(job: Stocks::SyncStockAnalysisJob, args: [@user.id, ["AAPL"]]) do
        post stocks_analyze_ticker_path("AAPL")
      end
    end

    assert_redirected_to stocks_path
    assert_match "Analysis started", flash[:notice]
  end

  test "analyze_ticker redirects with alert for unknown ticker" do
    sign_in_as(@user)

    StocksController.any_instance.stub(:allowed_analysis_tickers, ["AAPL"]) do
      post stocks_analyze_ticker_path("UNKNOWN")
    end

    assert_redirected_to stocks_path
    assert_match "Ticker not found", flash[:alert]
  end

  private

  def sign_in_as(user)
    post login_path, params: { email: user.email, password: "password" }
    follow_redirect!
  end
end
