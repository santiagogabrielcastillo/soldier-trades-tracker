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

  test "index returns 200 when signed in and shows portfolio tab with upload form and New transaction" do
    sign_in_as(@user)
    get spot_path
    assert_response :success
    assert_select "h1", text: /Spot portfolio/
    assert_select "nav[aria-label='Tabs']"
    assert_select "a", text: /Portfolio/
    assert_select "a", text: /Transactions/
    assert_select "form[action=?]", spot_import_path
    assert_select "button[aria-label='New transaction']", text: /New transaction/
    assert_select "form[action=?]", spot_transactions_path
  end

  test "index with view=transactions shows transactions tab and filter form" do
    sign_in_as(@user)
    get spot_path, params: { view: "transactions" }
    assert_response :success
    assert_select "h1", text: /Spot portfolio/
    assert_select "form[action=?][method=get]", spot_path
    assert_match(/From|To|Token|Side|Filter/, response.body)
  end

  test "index with view=transactions shows empty state when no transactions" do
    sign_in_as(@user)
    SpotAccount.find_or_create_default_for(@user).spot_transactions.destroy_all
    get spot_path, params: { view: "transactions" }
    assert_response :success
    assert_match(/No spot transactions yet/, response.body)
  end

  test "index with view=transactions shows transactions table when transactions exist" do
    sign_in_as(@user)
    account = SpotAccount.find_or_create_default_for(@user)
    account.spot_transactions.create!(
      token: "BTC", side: "buy", amount: 1, price_usd: 50_000, total_value_usd: 50_000,
      executed_at: 1.day.ago, row_signature: SecureRandom.hex(32)
    )
    get spot_path, params: { view: "transactions" }
    assert_response :success
    assert_match(/BTC/, response.body)
    assert_match(/buy/, response.body)
    assert_match(/50,000/, response.body)
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

  test "create with valid params creates transaction and redirects" do
    sign_in_as(@user)
    spot_account = SpotAccount.find_or_create_default_for(@user)
    assert_difference("spot_account.spot_transactions.count", 1) do
      post spot_transactions_path, params: {
        token: "BTC",
        side: "buy",
        amount: "1",
        price_usd: "50000",
        executed_at: "2026-03-10T12:00"
      }
    end
    assert_redirected_to spot_path
    assert_equal "Transaction added.", flash[:notice]
    tx = spot_account.spot_transactions.reorder(created_at: :desc).first
    assert_equal "BTC", tx.token
    assert_equal "buy", tx.side
    assert_equal 1, tx.amount.to_i
    assert_equal 50_000, tx.price_usd.to_i
    assert_equal 50_000, tx.total_value_usd.to_i
  end

  test "create with duplicate params redirects with alert" do
    sign_in_as(@user)
    spot_account = SpotAccount.find_or_create_default_for(@user)
    params = { token: "ETH", side: "sell", amount: "0.5", price_usd: "3000", executed_at: "2026-03-10T14:30" }
    post spot_transactions_path, params: params
    assert_redirected_to spot_path
    post spot_transactions_path, params: params
    assert_redirected_to spot_path
    assert_equal "This transaction already exists.", flash[:alert]
    assert_equal 1, spot_account.spot_transactions.where(token: "ETH", side: "sell").count
  end

  test "create with valid params as JSON returns 201" do
    sign_in_as(@user)
    spot_account = SpotAccount.find_or_create_default_for(@user)
    post spot_transactions_path, params: {
      token: "SOL",
      side: "buy",
      amount: "2",
      price_usd: "150",
      executed_at: "2026-03-11T09:00"
    }, as: :json
    assert_response :created
    assert_equal 1, spot_account.spot_transactions.where(token: "SOL").count
  end

  test "create with invalid params re-renders index with 422 and modal open" do
    sign_in_as(@user)
    SpotAccount.find_or_create_default_for(@user)
    post spot_transactions_path, params: {
      token: "",
      side: "buy",
      amount: "1",
      price_usd: "100",
      executed_at: "2026-03-10T12:00"
    }
    assert_response :unprocessable_entity
    assert_select "h1", text: /Spot portfolio/
    assert_select "form[action=?]", spot_transactions_path
    assert_select "[data-dialog-open-on-connect-value='true']"
  end

  def sign_in_as(user)
    post login_path, params: { email: user.email, password: "password" }
    follow_redirect!
  end
end
