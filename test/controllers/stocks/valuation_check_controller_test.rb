# frozen_string_literal: true

require "test_helper"

module Stocks
  class ValuationCheckControllerTest < ActionDispatch::IntegrationTest
    setup do
      @user = users(:one)
      @user.update!(password: "password", password_confirmation: "password")
    end

    test "show requires authentication" do
      get stocks_valuation_check_path
      assert_redirected_to login_path
    end

    test "show renders successfully without ticker" do
      sign_in_as(@user)
      get stocks_valuation_check_path
      assert_response :success
    end

    test "show renders successfully with valid ticker" do
      sign_in_as(@user)
      Stocks::CurrentPriceFetcher.stub(:call, { "AAPL" => BigDecimal("160") }) do
        get stocks_valuation_check_path(ticker: "AAPL")
      end
      assert_response :success
    end

    test "show pre-fills fwd_eps from fundamental and price" do
      sign_in_as(@user)
      Stocks::CurrentPriceFetcher.stub(:call, { "AAPL" => BigDecimal("160") }) do
        get stocks_valuation_check_path(ticker: "AAPL")
      end
      # AAPL fixture: fwd_pe: 25.1, so fwd_eps = 160 / 25.1 ≈ 6.37
      assert_select "input[name='fwd_eps']" do |inputs|
        assert inputs.first["value"].to_f.round(2) == 6.37
      end
    end

    test "show renders with blank pre-fill when no fundamental exists" do
      sign_in_as(@user)
      Stocks::CurrentPriceFetcher.stub(:call, {}) do
        get stocks_valuation_check_path(ticker: "NOPE")
      end
      assert_response :success
    end

    private

    def sign_in_as(user)
      post login_path, params: { email: user.email, password: "password" }
      follow_redirect!
    end
  end
end
