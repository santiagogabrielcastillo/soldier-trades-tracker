# frozen_string_literal: true

require "test_helper"

class SpotControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @user.update!(password: "password", password_confirmation: "password")
  end

  test "index redirects to login when not signed in" do
    get spot_path
    assert_redirected_to login_path
  end

  test "index returns 200 when signed in and shows upload form" do
    sign_in_as(@user)
    get spot_path
    assert_response :success
    assert_select "h1", text: /Spot portfolio/
    assert_select "form[action=?]", spot_import_path
    assert_select "input[type=file][name=?]", "csv_file"
  end

  test "import redirects with alert when no file" do
    sign_in_as(@user)
    post spot_import_path, params: {}
    assert_redirected_to spot_path
    assert_equal "Please select a CSV file.", flash[:alert]
  end

  test "import creates transactions and redirects with notice" do
    sign_in_as(@user)
    @user.spot_accounts.destroy_all
    SpotAccount.find_or_create_default_for(@user)
    csv = <<~CSV
      Date (UTC-3:00),Token,Type,Price (USD),Amount,Total value (USD),Fee,Fee Currency,Notes
      2026-01-14 10:05:00,AAVE,buy,174.52,2.292,400,--,,
    CSV
    post spot_import_path, params: { csv_file: Rack::Test::UploadedFile.new(StringIO.new(csv), "text/csv", original_filename: "test.csv") }
    assert_redirected_to spot_path
    assert_match(/Imported 1 row/, flash[:notice])
    assert_equal 1, @user.spot_accounts.first.spot_transactions.count
  end

  def sign_in_as(user)
    post login_path, params: { email: user.email, password: "password" }
    follow_redirect!
  end
end
