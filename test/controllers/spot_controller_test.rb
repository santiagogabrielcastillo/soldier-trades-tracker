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

  test "create with side deposit creates cash transaction" do
    sign_in_as(@user)
    spot_account = SpotAccount.find_or_create_default_for(@user)
    assert_difference("spot_account.spot_transactions.count", 1) do
      post spot_transactions_path, params: {
        side: "deposit",
        amount: "250",
        executed_at: "2026-03-12T10:00"
      }
    end
    assert_redirected_to spot_path
    assert_equal "Cash movement added.", flash[:notice]
    tx = spot_account.spot_transactions.reorder(created_at: :desc).first
    assert_equal "USDT", tx.token
    assert_equal "deposit", tx.side
    assert_equal 250, tx.amount.to_i
    assert_equal 1, tx.price_usd.to_i
    assert_equal 250, tx.total_value_usd.to_i
    assert tx.row_signature.start_with?("cash|")
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

  test "destroy deletes own transaction and redirects with notice" do
    sign_in_as(@user)
    account = SpotAccount.find_or_create_default_for(@user)
    tx = account.spot_transactions.create!(
      token: "BTC", side: "buy", amount: 1, price_usd: 50_000, total_value_usd: 50_000,
      executed_at: 1.day.ago, row_signature: SecureRandom.hex(32)
    )
    assert_difference("account.spot_transactions.count", -1) do
      delete destroy_spot_transaction_path(tx)
    end
    assert_redirected_to spot_path(view: "transactions")
    assert_equal "Transaction deleted.", flash[:notice]
  end

  test "destroy returns 404 for another user's transaction" do
    sign_in_as(@user)
    other_user = users(:two)
    other_user.update!(password: "password", password_confirmation: "password")
    other_account = SpotAccount.find_or_create_default_for(other_user)
    tx = other_account.spot_transactions.create!(
      token: "ETH", side: "buy", amount: 1, price_usd: 3_000, total_value_usd: 3_000,
      executed_at: 1.day.ago, row_signature: SecureRandom.hex(32)
    )
    assert_no_difference("SpotTransaction.count") do
      delete destroy_spot_transaction_path(tx)
    end
    assert_response :not_found
  end

  test "edit returns the edit form partial for own transaction" do
    sign_in_as(@user)
    account = SpotAccount.find_or_create_default_for(@user)
    tx = account.spot_transactions.create!(
      token: "BTC", side: "buy", amount: 1, price_usd: 50_000, total_value_usd: 50_000,
      executed_at: 1.day.ago, row_signature: SecureRandom.hex(32)
    )
    get edit_spot_transaction_path(tx)
    assert_response :success
    assert_match(/BTC/, response.body)
    assert_match(/50000/, response.body)
    assert_match(/spot-transaction-edit-frame/, response.body)
  end

  test "edit returns 404 for another user's transaction" do
    sign_in_as(@user)
    other_user = users(:two)
    other_user.update!(password: "password", password_confirmation: "password")
    other_account = SpotAccount.find_or_create_default_for(other_user)
    tx = other_account.spot_transactions.create!(
      token: "ETH", side: "buy", amount: 1, price_usd: 3_000, total_value_usd: 3_000,
      executed_at: 1.day.ago, row_signature: SecureRandom.hex(32)
    )
    get edit_spot_transaction_path(tx)
    assert_response :not_found
  end

  test "confirm_destroy returns delete confirm partial for own transaction" do
    sign_in_as(@user)
    account = SpotAccount.find_or_create_default_for(@user)
    tx = account.spot_transactions.create!(
      token: "BTC", side: "buy", amount: 1, price_usd: 50_000, total_value_usd: 50_000,
      executed_at: 1.day.ago, row_signature: SecureRandom.hex(32)
    )
    get confirm_destroy_spot_transaction_path(tx)
    assert_response :success
    assert_match(/BTC/, response.body)
    assert_match(/spot-transaction-delete-frame/, response.body)
    assert_match(/Confirm delete/, response.body)
  end

  test "confirm_destroy returns 404 for another user's transaction" do
    sign_in_as(@user)
    other_user = users(:two)
    other_user.update!(password: "password", password_confirmation: "password")
    other_account = SpotAccount.find_or_create_default_for(other_user)
    tx = other_account.spot_transactions.create!(
      token: "ETH", side: "buy", amount: 1, price_usd: 3_000, total_value_usd: 3_000,
      executed_at: 1.day.ago, row_signature: SecureRandom.hex(32)
    )
    get confirm_destroy_spot_transaction_path(tx)
    assert_response :not_found
  end

  test "update with valid params corrects price and recalculates total_value_usd and row_signature" do
    sign_in_as(@user)
    account = SpotAccount.find_or_create_default_for(@user)
    tx = account.spot_transactions.create!(
      token: "BTC", side: "buy", amount: BigDecimal("2"), price_usd: BigDecimal("50000"),
      total_value_usd: BigDecimal("100000"), executed_at: Time.zone.parse("2026-01-10 12:00"),
      row_signature: SecureRandom.hex(32)
    )
    old_sig = tx.row_signature

    patch spot_transaction_path(tx), params: {
      spot_transaction: { token: "BTC", price_usd: "55000", amount: "2", executed_at: "2026-01-10T12:00" }
    }

    assert_redirected_to spot_path(view: "transactions")
    assert_equal "Transaction updated.", flash[:notice]
    tx.reload
    assert_equal BigDecimal("55000"), tx.price_usd
    assert_equal BigDecimal("110000"), tx.total_value_usd
    assert_not_equal old_sig, tx.row_signature
  end

  test "update with duplicate values shows validation error and re-renders form" do
    sign_in_as(@user)
    account = SpotAccount.find_or_create_default_for(@user)
    existing = account.spot_transactions.create!(
      token: "BTC", side: "buy", amount: BigDecimal("1"), price_usd: BigDecimal("60000"),
      total_value_usd: BigDecimal("60000"), executed_at: Time.zone.parse("2026-01-10 12:00"),
      row_signature: Spot::CsvRowParser.row_signature(Time.zone.parse("2026-01-10 12:00"), "BTC", "buy", BigDecimal("60000"), BigDecimal("1"))
    )
    tx = account.spot_transactions.create!(
      token: "BTC", side: "buy", amount: BigDecimal("2"), price_usd: BigDecimal("50000"),
      total_value_usd: BigDecimal("100000"), executed_at: Time.zone.parse("2026-01-11 12:00"),
      row_signature: SecureRandom.hex(32)
    )

    # Attempt to update tx so its values collide with existing
    patch spot_transaction_path(tx), params: {
      spot_transaction: { token: "BTC", price_usd: "60000", amount: "1", executed_at: "2026-01-10T12:00" }
    }

    assert_response :unprocessable_entity
    assert_match(/spot-transaction-edit-frame/, response.body)
  end

  test "update cannot update another user's transaction" do
    sign_in_as(@user)
    other_user = users(:two)
    other_user.update!(password: "password", password_confirmation: "password")
    other_account = SpotAccount.find_or_create_default_for(other_user)
    tx = other_account.spot_transactions.create!(
      token: "ETH", side: "buy", amount: 1, price_usd: 3_000, total_value_usd: 3_000,
      executed_at: 1.day.ago, row_signature: SecureRandom.hex(32)
    )
    patch spot_transaction_path(tx), params: {
      spot_transaction: { token: "ETH", price_usd: "4000", amount: "1", executed_at: 1.day.ago.strftime("%Y-%m-%dT%H:%M") }
    }
    assert_response :not_found
    tx.reload
    assert_equal BigDecimal("3000"), tx.price_usd
  end

  test "update deposit transaction changes amount and recalculates total_value_usd" do
    sign_in_as(@user)
    account = SpotAccount.find_or_create_default_for(@user)
    tx = account.spot_transactions.create!(
      token: "USDT", side: "deposit", amount: BigDecimal("100"), price_usd: BigDecimal("1"),
      total_value_usd: BigDecimal("100"), executed_at: Time.zone.parse("2026-01-10 12:00"),
      row_signature: "cash|#{Time.zone.parse("2026-01-10 12:00").to_i}|abc123"
    )
    patch spot_transaction_path(tx), params: {
      spot_transaction: { amount: "250", executed_at: "2026-01-10T12:00" }
    }
    assert_redirected_to spot_path(view: "transactions")
    tx.reload
    assert_equal BigDecimal("250"), tx.amount
    assert_equal BigDecimal("250"), tx.total_value_usd
  end

  test "portfolio view renders scenario calculator data attributes with positions JSON" do
    sign_in_as(@user)
    account = SpotAccount.find_or_create_default_for(@user)
    account.spot_transactions.destroy_all
    account.spot_transactions.create!(
      token: "BTC", side: "buy", amount: 0.5, price_usd: 72_400,
      total_value_usd: 36_200, executed_at: 1.week.ago,
      row_signature: "btc_scenario_test_1"
    )
    account.update!(cached_prices: { "BTC" => "42100" }, prices_synced_at: Time.current)

    get spot_path
    assert_response :success
    # Controller assigns @scenario_positions_json — verified via assigns helper.
    # The data-spot-scenario-* HTML attributes and assert_match on JSON in body
    # will be testable once Task 2 adds the _scenario_calculator partial.
    assert_not_nil @controller.view_assigns["scenario_positions_json"]
    parsed = JSON.parse(@controller.view_assigns["scenario_positions_json"])
    btc = parsed.find { |p| p["token"] == "BTC" }
    assert_not_nil btc
    assert_match(/42100/, btc["current_price"])
  end

  def sign_in_as(user)
    post login_path, params: { email: user.email, password: "password" }
    follow_redirect!
  end
end
