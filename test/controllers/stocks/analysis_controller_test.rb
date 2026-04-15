# frozen_string_literal: true

require "test_helper"

module Stocks
  class AnalysisControllerTest < ActionDispatch::IntegrationTest
    setup do
      @user = users(:one)
      @user.update!(password: "password", password_confirmation: "password")
    end

    test "show requires authentication" do
      get stocks_analysis_path("AAPL")
      assert_redirected_to login_path
    end

    test "show renders successfully for an analysis owned by the user" do
      sign_in_as(@user)
      get stocks_analysis_path("AAPL")
      assert_response :success
    end

    test "show redirects with alert when analysis not found for user" do
      sign_in_as(@user)
      get stocks_analysis_path("NOPE")
      assert_redirected_to stocks_path
      assert_match "No analysis found", flash[:alert]
    end

    test "show does not expose another user's analysis" do
      other_user = users(:two)
      other_user.update!(password: "password", password_confirmation: "password")
      # AAPL analysis belongs to users(:one); signing in as two should get a redirect
      sign_in_as(other_user)
      get stocks_analysis_path("AAPL")
      assert_redirected_to stocks_path
      assert_match "No analysis found", flash[:alert]
    end

    private

    def sign_in_as(user)
      post login_path, params: { email: user.email, password: "password" }
      follow_redirect!
    end
  end
end
