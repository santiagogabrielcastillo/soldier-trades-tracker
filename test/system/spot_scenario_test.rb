# frozen_string_literal: true

require "application_system_test_case"

class SpotScenarioTest < ApplicationSystemTestCase
  setup do
    @user = users(:one)
    @user.update!(password: "password", password_confirmation: "password")

    @account = SpotAccount.find_or_create_default_for(@user)
    @account.spot_transactions.destroy_all

    # Cash deposit so we have a non-zero budget
    @account.spot_transactions.create!(
      token: "USDT", side: "deposit",
      executed_at: 2.days.ago, price_usd: 1, amount: 5000,
      total_value_usd: 5000, row_signature: "dep_#{SecureRandom.hex(8)}"
    )

    # Two open positions (buys, no sells)
    # BTC: breakeven=$50,000, current=$42,000 → ROI=-16%
    # WLD: breakeven=$1.00,   current=$0.75  → ROI=-25%
    @account.spot_transactions.create!(
      token: "BTC", side: "buy",
      executed_at: 1.day.ago, price_usd: 50_000, amount: 0.01,
      total_value_usd: 500, row_signature: "btc_buy_#{SecureRandom.hex(8)}"
    )
    @account.spot_transactions.create!(
      token: "WLD", side: "buy",
      executed_at: 1.day.ago, price_usd: 1.0, amount: 200,
      total_value_usd: 200, row_signature: "wld_buy_#{SecureRandom.hex(8)}"
    )

    @account.cache_prices!("BTC" => "42000", "WLD" => "0.75")
  end

  # ── 1. Panel toggle ──────────────────────────────────────────────────────

  test "panel is collapsed by default and toggles open and closed" do
    navigate_to_spot

    panel = find("[data-spot-scenario-target='panel']", visible: :all)
    assert panel[:class].include?("hidden"), "panel should start hidden"

    stimulus_call("toggle")
    assert_no_selector "[data-spot-scenario-target='panel'].hidden", visible: :all, wait: 5

    stimulus_call("toggle")
    assert_selector "[data-spot-scenario-target='panel'].hidden", visible: :all, wait: 5
  end

  # ── 2. Budget inputs stay in sync ───────────────────────────────────────

  test "typing target cash % updates budget to invest and vice versa" do
    navigate_to_spot
    open_panel

    js_set_value("[data-spot-scenario-target='targetCashPct']", "50")

    budget_val = page.evaluate_script(
      "parseFloat(document.querySelector(\"[data-spot-scenario-target='budgetAmount']\").value)"
    )
    assert budget_val > 0, "budget should be positive after setting target cash%"

    js_set_value("[data-spot-scenario-target='budgetAmount']", "1000")

    pct_val = page.evaluate_script(
      "parseFloat(document.querySelector(\"[data-spot-scenario-target='targetCashPct']\").value)"
    )
    assert pct_val > 0 && pct_val < 100, "target cash% should update when budget is typed"
  end

  # ── 3. Slider updates New ROI live ──────────────────────────────────────

  test "moving a slider updates the new ROI cell for that token" do
    navigate_to_spot
    open_panel
    js_set_budget(500)

    assert_selector "[data-new-roi='WLD']", wait: 5
    initial_roi = find("[data-new-roi='WLD']").text

    page.execute_script(<<~JS)
      const slider = document.querySelector("[data-token='WLD'][type='range']");
      const setter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value').set;
      setter.call(slider, 250);
      slider.dispatchEvent(new Event('input', { bubbles: true }));
    JS

    new_roi = find("[data-new-roi='WLD']").text
    assert_not_equal initial_roi, new_roi, "New ROI cell should update when slider moves"
  end

  # ── 4. Fixed-target optimizer shows badges ───────────────────────────────

  test "fixed target optimizer marks positions as met or exhausted" do
    navigate_to_spot
    open_panel
    js_set_budget(2000)

    stimulus_call("switchToOptimize")
    assert_selector "[data-spot-scenario-target='optimizeContent']:not(.hidden)", wait: 5

    # Target ROI = -10%; both BTC (-16%) and WLD (-25%) need injection to reach -10%
    js_set_value("[data-spot-scenario-target='targetRoi']", "-10")

    stimulus_call("runOptimizer")

    within("[data-spot-scenario-target='optimizeResults']", wait: 5) do
      has_badge = has_text?("Target met") || has_text?("Budget exhausted")
      assert has_badge, "optimizer results should show Target met or Budget exhausted badges"
    end
  end

  # ── 5. Best-floor optimizer shows Equalized badges ──────────────────────

  test "best achievable floor optimizer shows equalized badges when budget is sufficient" do
    navigate_to_spot
    open_panel
    js_set_budget(2000)

    stimulus_call("switchToOptimize")
    assert_selector "[data-spot-scenario-target='optimizeContent']:not(.hidden)", wait: 5

    stimulus_call("setModeFloor")
    stimulus_call("runOptimizer")

    within("[data-spot-scenario-target='optimizeResults']", wait: 5) do
      assert_text "Equalized", wait: 5
    end
  end

  private

  def sign_in
    visit login_path
    fill_in "Email", with: @user.email
    fill_in "Password", with: "password"
    click_button "Sign in"
    assert_selector "nav", wait: 5
  end

  def navigate_to_spot
    sign_in
    visit spot_path
    assert_selector "h1", text: /Spot portfolio/, wait: 10
    assert_selector "button", text: /Scenario calculator/, wait: 10
  end

  def open_panel
    stimulus_call("toggle")
    assert_no_selector "[data-spot-scenario-target='panel'].hidden", visible: :all, wait: 5
  end

  # Call a method on the spot-scenario Stimulus controller, polling until the
  # controller is connected (handles the case where Stimulus hasn't initialized yet).
  def stimulus_call(method)
    10.times do
      done = page.evaluate_script(<<~JS)
        (function() {
          const el = document.querySelector('[data-controller*="spot-scenario"]');
          const ctrl = window.Stimulus && window.Stimulus.getControllerForElementAndIdentifier(el, 'spot-scenario');
          if (ctrl) { ctrl['#{method}'](); return true; }
          return false;
        })()
      JS
      return if done
      sleep 0.3
    end
    raise "Stimulus spot-scenario controller not connected after 3s (method: #{method})"
  end

  # Set a value on an input and dispatch the `input` event via JS so Stimulus
  # action handlers fire reliably (Capybara fill_in can miss input events).
  def js_set_value(selector, value)
    page.execute_script(<<~JS, selector, value.to_s)
      const el = document.querySelector(arguments[0]);
      const setter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value').set;
      setter.call(el, arguments[1]);
      el.dispatchEvent(new Event('input', { bubbles: true }));
    JS
  end

  def js_set_budget(amount)
    js_set_value("[data-spot-scenario-target='budgetAmount']", amount)
  end
end
