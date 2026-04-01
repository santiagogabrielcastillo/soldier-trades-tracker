# App Hardening & Performance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Harden security, fix mobile UX, improve dashboard/allocation performance, and remove dead code — preparing the app for friends & family onboarding.

**Architecture:** Layered improvements across auth (reset_session, rack-attack), config (CSP/keys), service layer (caching + parallelism), frontend (mobile drawer), and dead code removal. Each task is independent and can be reviewed and deployed separately.

**Tech Stack:** Rails 7.2, Minitest, Stimulus, Tailwind CSS, Solid Queue, rack-attack (new gem), Rails.cache

---

## Phase 1 — Security (do before sharing with anyone)

---

### Task 1: Fix Session Fixation — reset_session on login, registration, and logout

**Files:**
- Modify: `app/controllers/sessions_controller.rb`
- Modify: `app/controllers/users_controller.rb`
- Test: `test/controllers/sessions_controller_test.rb` (create if missing)

- [ ] **Step 1: Write failing test for logout session clearing**

```ruby
# test/controllers/sessions_controller_test.rb
require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)  # or User.create!(email: "t@t.com", password: "password123")
  end

  test "login sets user_id in session" do
    post sessions_url, params: { email: @user.email, password: "password" }
    assert_equal @user.id, session[:user_id]
    assert_redirected_to root_url
  end

  test "logout clears entire session" do
    post sessions_url, params: { email: @user.email, password: "password" }
    assert_equal @user.id, session[:user_id]

    delete logout_url
    assert_nil session[:user_id]
    assert_redirected_to login_url
  end

  test "failed login does not set user_id" do
    post sessions_url, params: { email: @user.email, password: "wrong" }
    assert_nil session[:user_id]
    assert_response :unprocessable_entity
  end
end
```

- [ ] **Step 2: Run tests to see current state**

```bash
bin/rails test test/controllers/sessions_controller_test.rb
```

- [ ] **Step 3: Add reset_session to sessions_controller.rb**

Replace the full file content:

```ruby
# frozen_string_literal: true

class SessionsController < ApplicationController
  skip_before_action :require_login, only: %i[new create]

  def new
    @user = User.new
  end

  def create
    user = User.find_by(email: params[:email])
    if user&.authenticate(params[:password])
      reset_session
      session[:user_id] = user.id
      redirect_to root_path, notice: "Signed in successfully."
    else
      flash.now[:alert] = "Invalid email or password."
      @user = User.new(email: params[:email])
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    reset_session
    redirect_to login_path, notice: "Signed out."
  end
end
```

- [ ] **Step 4: Add reset_session to users_controller.rb**

Replace `session[:user_id] = @user.id` in the `create` action:

```ruby
# frozen_string_literal: true

class UsersController < ApplicationController
  skip_before_action :require_login, only: %i[new create]

  def new
    @user = User.new
  end

  def create
    raise ActionController::RoutingError, "Not Found" unless registration_open?

    @user = User.new(user_params)
    if @user.save
      reset_session
      session[:user_id] = @user.id
      redirect_to root_path, notice: "Account created. Welcome!"
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def registration_open?
    ENV["REGISTRATION_OPEN"] == "true"
  end

  def user_params
    params.require(:user).permit(:email, :password, :password_confirmation, :sync_interval)
  end
end
```

- [ ] **Step 5: Run tests and confirm they pass**

```bash
bin/rails test test/controllers/sessions_controller_test.rb
```

Expected: all pass.

- [ ] **Step 6: Run full test suite**

```bash
bin/rails test
```

- [ ] **Step 7: Commit**

```bash
git add app/controllers/sessions_controller.rb app/controllers/users_controller.rb test/controllers/sessions_controller_test.rb
git commit -m "security: reset_session on login, registration, and logout to prevent session fixation"
```

---

### Task 2: Login Rate Limiting with rack-attack

**Files:**
- Modify: `Gemfile`
- Create: `config/initializers/rack_attack.rb`
- Test: `test/integration/rack_attack_test.rb` (create)

- [ ] **Step 1: Add rack-attack to Gemfile**

Add after the `gem "bcrypt"` line:

```ruby
gem "rack-attack"
```

- [ ] **Step 2: Install the gem**

```bash
bundle install
```

Expected output includes: `Installing rack-attack`

- [ ] **Step 3: Create the initializer**

```ruby
# config/initializers/rack_attack.rb
# frozen_string_literal: true

class Rack::Attack
  # Throttle login attempts by IP: 10 requests per minute
  throttle("login/ip", limit: 10, period: 1.minute) do |req|
    req.ip if req.path == "/sessions" && req.post?
  end

  # Throttle login attempts by email: 5 per minute per email
  throttle("login/email", limit: 5, period: 1.minute) do |req|
    if req.path == "/sessions" && req.post?
      req.params["email"].to_s.downcase.presence
    end
  end

  # Return 429 with a plain message on throttle
  self.throttled_responder = lambda do |_req|
    [429, { "Content-Type" => "text/plain" }, ["Too many login attempts. Try again in a minute."]]
  end
end
```

- [ ] **Step 4: Mount rack-attack in application.rb**

Open `config/application.rb` and add inside the `Application` class body:

```ruby
config.middleware.use Rack::Attack
```

- [ ] **Step 5: Write a test for the throttle**

```ruby
# test/integration/rack_attack_test.rb
require "test_helper"

class RackAttackTest < ActionDispatch::IntegrationTest
  setup do
    # Clear rate limit cache between tests
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
  end

  test "allows normal login attempts" do
    post sessions_url, params: { email: "test@example.com", password: "wrong" }
    assert_not_equal 429, response.status
  end

  test "throttles excessive login attempts by IP" do
    11.times do
      post sessions_url,
           params: { email: "attacker@example.com", password: "wrong" },
           headers: { "REMOTE_ADDR" => "1.2.3.4" }
    end
    assert_response 429
  end
end
```

- [ ] **Step 6: Run the rack-attack test**

```bash
bin/rails test test/integration/rack_attack_test.rb
```

Expected: both tests pass.

- [ ] **Step 7: Run full test suite**

```bash
bin/rails test
```

- [ ] **Step 8: Commit**

```bash
git add Gemfile Gemfile.lock config/initializers/rack_attack.rb config/application.rb test/integration/rack_attack_test.rb
git commit -m "security: add rack-attack login rate limiting (10 req/min per IP, 5 per email)"
```

---

### Task 3: Remove Hardcoded Encryption Key Fallbacks

**Files:**
- Modify: `config/environments/development.rb`

**Context:** Lines 69–71 have literal string fallbacks for Active Record encryption keys. If `ACTIVE_RECORD_ENCRYPTION_*` env vars aren't set, the app silently uses these publicly committed strings to encrypt exchange API keys.

- [ ] **Step 1: Check your local .env or credentials file for the keys**

```bash
grep -r "ACTIVE_RECORD_ENCRYPTION" .env* config/credentials.yml.enc 2>/dev/null || echo "Check your local env setup"
```

If you don't have them set locally, generate new ones:

```bash
bin/rails db:encryption:init
```

Copy the output values into your `.env` file (or wherever you store local env vars):
```
ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=<generated>
ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY=<generated>
ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT=<generated>
```

- [ ] **Step 2: Replace the three config lines in development.rb**

Change lines 69–71 from:

```ruby
config.active_record.encryption.primary_key = ENV.fetch("ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY", "l7FQN8CAj7pPSjMpejYmrRbRQN4JEMWr")
config.active_record.encryption.deterministic_key = ENV.fetch("ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY", "6nQtPbHgtOntGtZ3ze7UFvyXNVc0xiU9")
config.active_record.encryption.key_derivation_salt = ENV.fetch("ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT", "JxY5ufaqnwLZhRf9ymTteRy7pGUrUwUN")
```

To (no default fallbacks — fail loudly if env vars missing):

```ruby
config.active_record.encryption.primary_key = ENV.fetch("ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY")
config.active_record.encryption.deterministic_key = ENV.fetch("ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY")
config.active_record.encryption.key_derivation_salt = ENV.fetch("ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT")
```

- [ ] **Step 3: Start the development server to confirm it boots**

```bash
./bin/dev
```

Expected: server starts on port 5000 without errors. If it raises `KeyError`, set the env vars (Step 1).

- [ ] **Step 4: Run full test suite**

```bash
bin/rails test
```

- [ ] **Step 5: Commit**

```bash
git add config/environments/development.rb
git commit -m "security: remove hardcoded Active Record encryption key fallbacks — require env vars explicitly"
```

---

### Task 4: Enable Content Security Policy and Permissions Policy

**Files:**
- Modify: `config/initializers/content_security_policy.rb`
- Modify: `config/initializers/permissions_policy.rb`

- [ ] **Step 1: Configure content_security_policy.rb**

Replace the entire file with:

```ruby
# frozen_string_literal: true

Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.font_src    :self, :https, :data, "https://fonts.gstatic.com"
    policy.img_src     :self, :https, :data
    policy.object_src  :none
    policy.script_src  :self, :https
    policy.style_src   :self, :https, "https://fonts.googleapis.com"
    policy.connect_src :self, :https
    policy.frame_ancestors :none
  end

  # Session-based nonce for importmap and inline scripts
  config.content_security_policy_nonce_generator = ->(request) { request.session.id.to_s }
  config.content_security_policy_nonce_directives = %w[script-src style-src]
end
```

- [ ] **Step 2: Configure permissions_policy.rb**

Replace the entire file with:

```ruby
# frozen_string_literal: true

Rails.application.config.permissions_policy do |policy|
  policy.camera      :none
  policy.gyroscope   :none
  policy.microphone  :none
  policy.usb         :none
  policy.fullscreen  :self
  policy.payment     :none
end
```

- [ ] **Step 3: Start the dev server and verify the app loads**

```bash
./bin/dev
```

Open `http://localhost:5000`. Check browser DevTools → Console for CSP violation errors. If Chart.js or importmap scripts are blocked, you may need to add `:unsafe-inline` temporarily or ensure nonces are applied. The nonce generator handles importmap scripts automatically in Rails 7.2.

- [ ] **Step 4: Run full test suite**

```bash
bin/rails test
```

- [ ] **Step 5: Commit**

```bash
git add config/initializers/content_security_policy.rb config/initializers/permissions_policy.rb
git commit -m "security: enable Content Security Policy and Permissions Policy"
```

---

## Phase 2 — Mobile Navigation

---

### Task 5: Mobile Hamburger Drawer

**Files:**
- Create: `app/javascript/controllers/nav_controller.js`
- Modify: `app/views/layouts/application.html.erb`

**Context:** The sidebar is `lg:flex hidden` — invisible below 1024px. The mobile header shows "Menu below ↓" but there's no actual navigation. We need a slide-in drawer controlled by Stimulus.

- [ ] **Step 1: Create the Stimulus nav controller**

```javascript
// app/javascript/controllers/nav_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["drawer", "overlay"]

  open() {
    this.drawerTarget.classList.remove("-translate-x-full")
    this.overlayTarget.classList.remove("hidden")
    document.body.classList.add("overflow-hidden")
    // Move focus to the drawer for keyboard navigation
    this.drawerTarget.querySelector("a, button")?.focus()
  }

  close() {
    this.drawerTarget.classList.add("-translate-x-full")
    this.overlayTarget.classList.add("hidden")
    document.body.classList.remove("overflow-hidden")
  }
}
```

Note: `eagerLoadControllersFrom` in `index.js` auto-registers this controller as `nav`. No changes to `index.js` needed.

- [ ] **Step 2: Update the layout — replace mobile header and add drawer**

In `app/views/layouts/application.html.erb`, find the `<% if current_user %>` block and replace the mobile header and the `<aside>` through to the content `<div>` with the following:

Replace lines 26–93 (the entire authenticated layout block) with:

```erb
<% if current_user %>
  <%# ── Nav wrapper (controls mobile drawer) ─────────────────────────────── %>
  <div data-controller="nav">

    <%# ── Mobile drawer overlay ──────────────────────────────────────────── %>
    <div data-nav-target="overlay"
         class="fixed inset-0 z-40 hidden bg-black/50 lg:hidden"
         data-action="click->nav#close"
         aria-hidden="true"></div>

    <%# ── Mobile drawer (slide-in from left) ────────────────────────────── %>
    <div data-nav-target="drawer"
         class="fixed inset-y-0 left-0 z-50 w-56 -translate-x-full transform bg-slate-900 transition-transform duration-200 ease-in-out lg:hidden"
         aria-label="Mobile navigation"
         role="dialog"
         aria-modal="true">
      <%= link_to root_path, class: "flex h-14 shrink-0 items-center gap-2 border-b border-slate-800 px-5 hover:opacity-80" do %>
        <svg class="h-3.5 w-3.5 text-indigo-400" fill="currentColor" viewBox="0 0 16 16" aria-hidden="true"><polygon points="8,1 15,14 1,14"/></svg>
        <span class="text-[14px] font-bold tracking-tight text-white">Soldier<span class="text-indigo-400">Trades</span></span>
      <% end %>
      <nav class="flex flex-1 flex-col overflow-y-auto" aria-label="Main navigation">
        <div class="flex-1 space-y-0.5 px-3 py-4">
          <% [
            ["Dashboard",         root_path,             root_path],
            ["Exchange accounts", exchange_accounts_path, "/exchange_accounts"],
            ["Trades",            trades_path,            "/trades"],
            ["Spot",              spot_path,              "/spot"],
            ["Stocks",            stocks_path,            "/stocks"],
            ["Allocation",        allocation_path,        "/allocation"],
            ["Portfolios",        portfolios_path,        "/portfolios"],
          ].each do |label, path, match| %>
            <% active = match == root_path ? current_page?(root_path) : request.path.start_with?(match) %>
            <%= link_to label, path,
                  class: "flex items-center rounded-md px-3 py-2 text-sm transition-colors duration-150 #{active ? 'bg-slate-700 font-medium text-white' : 'text-slate-400 hover:bg-slate-800 hover:text-slate-100'}",
                  data: { action: "nav#close" } %>
          <% end %>
        </div>
        <div class="space-y-0.5 border-t border-slate-800 px-3 py-4">
          <% active_settings = request.path.start_with?("/settings") %>
          <%= link_to "Settings", settings_path,
                class: "flex items-center rounded-md px-3 py-2 text-sm transition-colors duration-150 #{active_settings ? 'bg-slate-700 font-medium text-white' : 'text-slate-400 hover:bg-slate-800 hover:text-slate-100'}",
                data: { action: "nav#close" } %>
          <%= button_to "Sign out", logout_path, method: :delete,
                class: "flex w-full items-center rounded-md px-3 py-2 text-left text-sm text-slate-400 transition-colors duration-150 hover:bg-slate-800 hover:text-slate-100" %>
        </div>
      </nav>
    </div>

    <%# ── Mobile header (visible below lg) ──────────────────────────────── %>
    <header class="sticky top-0 z-30 flex h-12 items-center justify-between border-b border-slate-200 bg-white px-4 lg:hidden">
      <%= link_to root_path, class: "flex items-center gap-1.5" do %>
        <svg class="h-3.5 w-3.5 text-indigo-600" fill="currentColor" viewBox="0 0 16 16" aria-hidden="true"><polygon points="8,1 15,14 1,14"/></svg>
        <span class="text-[14px] font-bold tracking-tight text-slate-900">Soldier<span class="text-indigo-600">Trades</span></span>
      <% end %>
      <button type="button"
              data-action="nav#open"
              class="flex h-8 w-8 items-center justify-center rounded-md text-slate-600 hover:bg-slate-100"
              aria-label="Open navigation menu">
        <svg class="h-5 w-5" fill="none" stroke="currentColor" viewBox="0 0 24 24" aria-hidden="true">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 6h16M4 12h16M4 18h16"/>
        </svg>
      </button>
    </header>

    <%# ── Desktop sidebar (visible lg+) ─────────────────────────────────── %>
    <aside class="fixed inset-y-0 left-0 z-50 hidden w-56 flex-col bg-slate-900 lg:flex">
      <%= link_to root_path, class: "flex h-14 shrink-0 items-center gap-2 border-b border-slate-800 px-5 transition-opacity duration-150 hover:opacity-80" do %>
        <svg class="h-3.5 w-3.5 text-indigo-400" fill="currentColor" viewBox="0 0 16 16" aria-hidden="true"><polygon points="8,1 15,14 1,14"/></svg>
        <span class="text-[14px] font-bold tracking-tight text-white">Soldier<span class="text-indigo-400">Trades</span></span>
      <% end %>
      <nav class="flex flex-1 flex-col overflow-y-auto" aria-label="Main navigation">
        <div class="flex-1 space-y-0.5 px-3 py-4">
          <% [
            ["Dashboard",         root_path,             root_path],
            ["Exchange accounts", exchange_accounts_path, "/exchange_accounts"],
            ["Trades",            trades_path,            "/trades"],
            ["Spot",              spot_path,              "/spot"],
            ["Stocks",            stocks_path,            "/stocks"],
            ["Allocation",        allocation_path,        "/allocation"],
            ["Portfolios",        portfolios_path,        "/portfolios"],
          ].each do |label, path, match| %>
            <% active = match == root_path ? current_page?(root_path) : request.path.start_with?(match) %>
            <%= link_to label, path,
                  class: "flex items-center rounded-md px-3 py-2 text-sm transition-colors duration-150 #{active ? 'bg-slate-700 font-medium text-white' : 'text-slate-400 hover:bg-slate-800 hover:text-slate-100'}" %>
          <% end %>
        </div>
        <div class="space-y-0.5 border-t border-slate-800 px-3 py-4">
          <% active_settings = request.path.start_with?("/settings") %>
          <%= link_to "Settings", settings_path,
                class: "flex items-center rounded-md px-3 py-2 text-sm transition-colors duration-150 #{active_settings ? 'bg-slate-700 font-medium text-white' : 'text-slate-400 hover:bg-slate-800 hover:text-slate-100'}" %>
          <%= button_to "Sign out", logout_path, method: :delete,
                class: "flex w-full items-center rounded-md px-3 py-2 text-left text-sm text-slate-400 transition-colors duration-150 hover:bg-slate-800 hover:text-slate-100" %>
        </div>
      </nav>
    </aside>

    <%# ── Content area ──────────────────────────────────────────────────── %>
    <div class="flex min-h-screen flex-col lg:ml-56">
      <% if flash[:notice] %>
        <div class="border-b border-emerald-200 bg-emerald-50" role="alert">
          <p class="px-6 py-2.5 text-sm font-medium text-emerald-700"><%= flash[:notice] %></p>
        </div>
      <% end %>
      <% if flash[:alert] %>
        <div class="border-b border-amber-200 bg-amber-50" role="alert">
          <p class="px-6 py-2.5 text-sm font-medium text-amber-700"><%= flash[:alert] %></p>
        </div>
      <% end %>
      <% if flash[:info] %>
        <div class="border-b border-indigo-200 bg-indigo-50" aria-live="polite">
          <p class="px-6 py-2.5 text-sm font-medium text-indigo-700"><%= flash[:info] %></p>
        </div>
      <% end %>
      <main class="mx-auto w-full max-w-6xl flex-1 px-6 py-8">
        <%= yield %>
      </main>
    </div>

  </div><%# end data-controller="nav" %>
```

- [ ] **Step 3: Verify in the browser at mobile width**

```bash
./bin/dev
```

Open DevTools → toggle device toolbar → set width to 375px (iPhone). You should see:
- The hamburger button (≡) in the top-right of the header
- Clicking it slides in the dark drawer from the left
- Clicking any nav link closes the drawer
- Clicking the overlay closes the drawer
- At desktop width (1024px+), drawer is hidden and sidebar shows as before

- [ ] **Step 4: Run full test suite**

```bash
bin/rails test
```

- [ ] **Step 5: Commit**

```bash
git add app/javascript/controllers/nav_controller.js app/views/layouts/application.html.erb
git commit -m "feat: mobile hamburger navigation drawer with Stimulus nav controller"
```

---

## Phase 3 — Performance

---

### Task 6: Cache and Parallelize Stocks::CurrentPriceFetcher

**Files:**
- Modify: `app/services/stocks/current_price_fetcher.rb`
- Test: `test/services/stocks/current_price_fetcher_test.rb` (create)

**Context:** Currently makes one sequential Finnhub HTTP call per ticker. With 5 tickers that's ~1 second of blocking I/O on every page load. `ArgentineCurrentPriceFetcher` already shows the right pattern: parallel threads + per-ticker cache.

- [ ] **Step 1: Write failing tests**

```ruby
# test/services/stocks/current_price_fetcher_test.rb
require "test_helper"

module Stocks
  class CurrentPriceFetcherTest < ActiveSupport::TestCase
    setup do
      Rails.cache.clear
    end

    test "returns empty hash for blank tickers" do
      assert_equal({}, CurrentPriceFetcher.call(tickers: []))
    end

    test "returns prices for valid tickers" do
      stub_finnhub("AAPL", 180.0)

      result = CurrentPriceFetcher.call(tickers: ["AAPL"])
      assert_equal BigDecimal("180.0"), result["AAPL"]
    end

    test "caches results for 5 minutes" do
      call_count = 0
      FinnhubClient.any_instance.stubs(:quote).with("AAPL") do
        call_count += 1
        BigDecimal("180.0")
      end

      CurrentPriceFetcher.call(tickers: ["AAPL"])
      CurrentPriceFetcher.call(tickers: ["AAPL"])

      assert_equal 1, call_count, "Expected Finnhub to be called once (second call from cache)"
    end

    test "omits tickers with nil price" do
      FinnhubClient.any_instance.stubs(:quote).with("UNKNOWN").returns(nil)

      result = CurrentPriceFetcher.call(tickers: ["UNKNOWN"])
      assert_equal({}, result)
    end

    private

    def stub_finnhub(ticker, price)
      FinnhubClient.any_instance.stubs(:quote).with(ticker).returns(BigDecimal(price.to_s))
    end
  end
end
```

- [ ] **Step 2: Run tests to see them fail**

```bash
bin/rails test test/services/stocks/current_price_fetcher_test.rb
```

The caching test will fail (no cache yet).

- [ ] **Step 3: Replace current_price_fetcher.rb with cached + parallel implementation**

```ruby
# frozen_string_literal: true

module Stocks
  # Fetches current prices for a list of stock tickers via Finnhub.
  # Fetches all tickers in parallel threads; caches each price for 5 minutes.
  # Returns Hash ticker => BigDecimal price; missing tickers are omitted.
  class CurrentPriceFetcher
    def self.call(tickers:)
      new(tickers: tickers).call
    end

    def initialize(tickers:)
      @tickers = tickers.to_a.uniq.map { |t| t.to_s.strip.upcase }.reject(&:blank?)
    end

    def call
      return {} if @tickers.empty?

      client = FinnhubClient.new
      mutex  = Mutex.new
      prices = {}

      threads = @tickers.map do |ticker|
        Thread.new do
          price = Rails.cache.fetch("finnhub_price:#{ticker}", expires_in: 5.minutes, skip_nil: true) do
            client.quote(ticker)
          end
          mutex.synchronize { prices[ticker] = price } if price
        end
      end
      threads.each(&:join)

      prices
    end
  end
end
```

- [ ] **Step 4: Run tests and confirm they pass**

```bash
bin/rails test test/services/stocks/current_price_fetcher_test.rb
```

Note: the caching test requires `Rails.cache` to be a non-null store. In test env this may use `:memory_store` by default. If tests run with `:null_store`, add to `config/environments/test.rb`:
```ruby
config.cache_store = :memory_store
```

- [ ] **Step 5: Run full test suite**

```bash
bin/rails test
```

- [ ] **Step 6: Commit**

```bash
git add app/services/stocks/current_price_fetcher.rb test/services/stocks/current_price_fetcher_test.rb
git commit -m "perf: cache and parallelize Stocks::CurrentPriceFetcher — 5-min per-ticker cache, parallel threads like ArgentineCurrentPriceFetcher"
```

---

### Task 7: Cache Spot::CurrentPriceFetcher and Remove Unused kwargs

**Files:**
- Modify: `app/services/spot/current_price_fetcher.rb`
- Modify: `app/services/dashboards/summary_service.rb` (remove `user:` kwarg from call site)
- Modify: `app/controllers/spot_controller.rb` (remove `user:` kwarg from call site)
- Test: `test/services/spot/current_price_fetcher_test.rb` (create)

**Context:** Dashboard calls `Spot::CurrentPriceFetcher.call` on every load with no cache. The `user:` kwarg is accepted but silently ignored. CoinGecko prices are valid for minutes — a 2-minute cache eliminates the live call on every refresh.

- [ ] **Step 1: Write failing tests**

```ruby
# test/services/spot/current_price_fetcher_test.rb
require "test_helper"

module Spot
  class CurrentPriceFetcherTest < ActiveSupport::TestCase
    setup do
      Rails.cache.clear
    end

    test "returns empty hash for blank tokens" do
      assert_equal({}, CurrentPriceFetcher.call(tokens: []))
    end

    test "caches results for 2 minutes" do
      call_count = 0
      Exchanges::Binance::SpotTickerFetcher.stubs(:fetch_prices).with(tokens: ["BTC"]) do
        call_count += 1
        { "BTC" => BigDecimal("50000") }
      end

      CurrentPriceFetcher.call(tokens: ["BTC"])
      CurrentPriceFetcher.call(tokens: ["BTC"])

      assert_equal 1, call_count, "Expected SpotTickerFetcher to be called once (second from cache)"
    end

    test "cache key is order-independent" do
      call_count = 0
      Exchanges::Binance::SpotTickerFetcher.stubs(:fetch_prices) do
        call_count += 1
        {}
      end

      CurrentPriceFetcher.call(tokens: ["ETH", "BTC"])
      CurrentPriceFetcher.call(tokens: ["BTC", "ETH"])

      assert_equal 1, call_count, "Same token set in different order should share cache"
    end
  end
end
```

- [ ] **Step 2: Run tests to see them fail**

```bash
bin/rails test test/services/spot/current_price_fetcher_test.rb
```

- [ ] **Step 3: Replace spot/current_price_fetcher.rb**

```ruby
# frozen_string_literal: true

module Spot
  # Fetches current spot prices for a list of tokens via the public Binance ticker API.
  # No exchange account required — the endpoint is unauthenticated.
  # Results are cached for 2 minutes keyed on the sorted token list.
  # Returns Hash token => BigDecimal price; empty on fetch failure.
  class CurrentPriceFetcher
    def self.call(tokens:)
      new(tokens: tokens).call
    end

    def initialize(tokens:)
      @tokens = tokens.to_a.uniq.map { |t| t.to_s.strip.upcase }.reject(&:blank?)
    end

    def call
      return {} if @tokens.empty?

      cache_key = "spot_prices:#{@tokens.sort.join(',')}"
      Rails.cache.fetch(cache_key, expires_in: 2.minutes) do
        Exchanges::Binance::SpotTickerFetcher.fetch_prices(tokens: @tokens)
      end
    end
  end
end
```

- [ ] **Step 4: Remove the `user:` kwarg from all call sites**

In `app/services/dashboards/summary_service.rb`, find:
```ruby
Spot::CurrentPriceFetcher.call(tokens: open_tokens, user: @user)
```
Replace with:
```ruby
Spot::CurrentPriceFetcher.call(tokens: open_tokens)
```

In `app/controllers/spot_controller.rb`, find any call passing `user:` and remove it.

Search for all call sites:
```bash
grep -rn "CurrentPriceFetcher.call" app/
```
Remove `user: ...` from any match.

- [ ] **Step 5: Run tests**

```bash
bin/rails test test/services/spot/current_price_fetcher_test.rb
bin/rails test
```

- [ ] **Step 6: Commit**

```bash
git add app/services/spot/current_price_fetcher.rb app/services/dashboards/summary_service.rb app/controllers/spot_controller.rb test/services/spot/current_price_fetcher_test.rb
git commit -m "perf: cache Spot::CurrentPriceFetcher (2-min TTL) and remove unused user: kwarg"
```

---

### Task 8: Batch Spot Price Fetching in Allocations::SummaryService

**Files:**
- Modify: `app/services/allocations/summary_service.rb`
- Test: `test/services/allocations/summary_service_test.rb` (create)

**Context:** `spot_account_usd` is called once per spot account, and each call fires a live `Spot::CurrentPriceFetcher` request. With 3 spot accounts, that's 3 separate CoinGecko calls per allocation page load. We precompute all spot USD values in one pass: load positions for all accounts, collect all unique tokens, fetch prices once, distribute.

- [ ] **Step 1: Write failing test**

```ruby
# test/services/allocations/summary_service_test.rb
require "test_helper"

module Allocations
  class SummaryServiceTest < ActiveSupport::TestCase
    test "fetches spot prices exactly once regardless of number of spot accounts" do
      user = users(:one)
      # Ensure two spot accounts exist
      spot1 = user.spot_accounts.find_or_create_by!(name: "Account A", default: false)
      spot2 = user.spot_accounts.find_or_create_by!(name: "Account B", default: false)

      fetch_call_count = 0
      Spot::CurrentPriceFetcher.stubs(:call) do
        fetch_call_count += 1
        {}
      end
      Spot::PositionStateService.stubs(:call).returns([])

      SummaryService.call(user: user)

      assert_operator fetch_call_count, :<=, 1, "Expected at most 1 price fetch call, got #{fetch_call_count}"
    end
  end
end
```

- [ ] **Step 2: Run test to see it fail (will get 2+ calls)**

```bash
bin/rails test test/services/allocations/summary_service_test.rb
```

- [ ] **Step 3: Refactor allocations/summary_service.rb**

Replace the `call` method and add `compute_all_spot_usd` private method:

```ruby
# frozen_string_literal: true

module Allocations
  class SummaryService
    BucketData = Struct.new(
      :id, :name, :color, :target_pct,
      :actual_usd, :actual_pct, :drift_pct, :sources,
      keyword_init: true
    )

    SourceData = Struct.new(:label, :amount_usd, :source_type, keyword_init: true)

    Result = Struct.new(:buckets, :total_usd, :unassigned_sources, keyword_init: true)

    def self.call(user:, mep_rate: nil)
      new(user: user, mep_rate: mep_rate).call
    end

    def initialize(user:, mep_rate: nil)
      @user = user
      @mep_rate = mep_rate
    end

    def call
      buckets              = @user.allocation_buckets.ordered
      manual_by_bucket     = @user.allocation_manual_entries.group_by(&:allocation_bucket_id)
      portfolios_by_bucket = @user.stock_portfolios.where.not(allocation_bucket_id: nil)
                                   .group_by(&:allocation_bucket_id)
      spot_by_bucket       = @user.spot_accounts.where.not(allocation_bucket_id: nil)
                                   .group_by(&:allocation_bucket_id)

      # Batch: compute USD value for every spot account in a single price fetch
      all_spot_accounts = @user.spot_accounts.to_a
      spot_usd_by_id    = compute_all_spot_usd(all_spot_accounts)

      bucket_data = buckets.map do |bucket|
        sources = []

        (manual_by_bucket[bucket.id] || []).each do |entry|
          sources << SourceData.new(label: entry.label, amount_usd: entry.amount_usd.to_d, source_type: :manual)
        end

        (portfolios_by_bucket[bucket.id] || []).each do |portfolio|
          usd = stock_portfolio_usd(portfolio)
          sources << SourceData.new(label: portfolio.name, amount_usd: usd, source_type: :stock_portfolio) if usd
        end

        (spot_by_bucket[bucket.id] || []).each do |spot|
          sources << SourceData.new(label: spot.name, amount_usd: spot_usd_by_id[spot.id], source_type: :spot_account)
        end

        BucketData.new(
          id: bucket.id, name: bucket.name, color: bucket.color,
          target_pct: bucket.target_pct&.to_d,
          actual_usd: sources.sum { |s| s.amount_usd },
          actual_pct: nil, drift_pct: nil, sources: sources
        )
      end

      total_usd = bucket_data.sum(&:actual_usd)

      bucket_data.each do |bd|
        bd.actual_pct = total_usd.positive? ? (bd.actual_usd / total_usd * 100).round(2) : BigDecimal("0")
        bd.drift_pct  = bd.target_pct ? (bd.actual_pct - bd.target_pct).round(2) : nil
      end

      unassigned = unassigned_sources(spot_usd_by_id)
      Result.new(buckets: bucket_data, total_usd: total_usd, unassigned_sources: unassigned)
    end

    private

    # Fetches spot prices once for all accounts and returns a Hash of spot_account_id => USD value.
    def compute_all_spot_usd(spot_accounts)
      return {} if spot_accounts.empty?

      positions_by_account = spot_accounts.index_with do |spot|
        Spot::PositionStateService.call(spot_account: spot)
      end

      all_open_tokens = positions_by_account.values.flatten.select(&:open?).map(&:token).uniq
      prices = all_open_tokens.any? ? Spot::CurrentPriceFetcher.call(tokens: all_open_tokens) : {}

      spot_accounts.index_with do |spot|
        open_positions = positions_by_account[spot].select(&:open?)
        crypto_value   = open_positions.sum(BigDecimal("0")) { |pos| (prices[pos.token] || 0).to_d * pos.balance }
        crypto_value + spot.cash_balance.to_d
      end
    end

    def stock_portfolio_usd(portfolio)
      snapshot = portfolio.stock_portfolio_snapshots.order(recorded_at: :desc).first
      return nil unless snapshot

      value = snapshot.total_value.to_d
      if portfolio.market == "argentina"
        return nil unless @mep_rate&.positive?
        (value / @mep_rate).round(2)
      else
        value
      end
    end

    def unassigned_sources(spot_usd_by_id)
      sources = []
      @user.stock_portfolios.where(allocation_bucket_id: nil).each do |p|
        usd = stock_portfolio_usd(p)
        sources << SourceData.new(label: "#{p.name} (stocks)", amount_usd: usd || BigDecimal("0"), source_type: :stock_portfolio)
      end
      @user.spot_accounts.where(allocation_bucket_id: nil).each do |s|
        sources << SourceData.new(label: "#{s.name} (spot)", amount_usd: spot_usd_by_id[s.id] || BigDecimal("0"), source_type: :spot_account)
      end
      sources
    end
  end
end
```

- [ ] **Step 4: Run tests**

```bash
bin/rails test test/services/allocations/summary_service_test.rb
bin/rails test
```

- [ ] **Step 5: Commit**

```bash
git add app/services/allocations/summary_service.rb test/services/allocations/summary_service_test.rb
git commit -m "perf: batch spot price fetching in Allocations::SummaryService — single CoinGecko call for all accounts"
```

---

### Task 9: Parallelize Dashboard + Fix OpenStruct + Fix Double MepRate Call

**Files:**
- Modify: `app/controllers/dashboards_controller.rb`
- Test: `test/controllers/dashboards_controller_test.rb` (create if missing)

**Context:** The dashboard runs `SummaryService` and `AllocationService` sequentially. These are independent — running them in parallel threads halves the wall-clock time. Also fixes: `OpenStruct` replaced with anonymous `Struct`, bare `rescue nil` replaced with scoped rescue, double `MepRateFetcher` call eliminated.

- [ ] **Step 1: Write test for dashboard show action**

```ruby
# test/controllers/dashboards_controller_test.rb
require "test_helper"

class DashboardsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in_as(@user)  # helper: post sessions_url, params: { email: @user.email, password: "password" }
  end

  test "GET / renders dashboard successfully" do
    Dashboards::SummaryService.stubs(:call).returns({
      exchange_accounts: [],
      default_portfolio: nil,
      summary_label: "All time",
      summary_date_range: nil,
      summary_balance: BigDecimal("0"),
      summary_period_pl: BigDecimal("0"),
      summary_total_return_pct: nil,
      summary_unrealized_pl: nil,
      summary_position_count: 0,
      summary_win_rate: nil,
      summary_avg_win: nil,
      summary_avg_loss: nil,
      summary_closed_count: 0,
      summary_trades_path_params: {},
      chart_balance_series: [],
      chart_cumulative_pl_series: [],
      spot_chart_series: [],
      spot_value: nil,
      spot_cost_basis: nil,
      spot_unrealized_pl: nil,
      spot_roi_pct: nil,
      stocks_value: nil,
      stocks_pl: nil,
      stocks_pl_pct: nil
    })
    Allocations::SummaryService.stubs(:call).returns(
      Allocations::SummaryService::Result.new(buckets: [], total_usd: BigDecimal("0"), unassigned_sources: [])
    )
    Stocks::MepRateFetcher.stubs(:call).returns(BigDecimal("1050"))

    get root_url
    assert_response :success
  end
end
```

- [ ] **Step 2: Run test to see current state**

```bash
bin/rails test test/controllers/dashboards_controller_test.rb
```

- [ ] **Step 3: Replace dashboards_controller.rb**

```ruby
# frozen_string_literal: true

class DashboardsController < ApplicationController
  def show
    mep_rate = begin
      Stocks::MepRateFetcher.call
    rescue StandardError => e
      Rails.logger.warn("[DashboardsController] MEP rate unavailable: #{e.message}")
      nil
    end

    summary_thread    = Thread.new { Dashboards::SummaryService.call(current_user) }
    allocation_thread = Thread.new { Allocations::SummaryService.call(user: current_user, mep_rate: mep_rate) }

    result = summary_thread.value
    result[:summary_trades_path] = trades_path(result[:summary_trades_path_params])
    @dashboard = Struct.new(*result.keys, keyword_init: true).new(**result)

    @allocation_summary = allocation_thread.value
  end
end
```

Note: `require "ostruct"` at the top of the old file should be removed — it's no longer needed.

- [ ] **Step 4: Run tests**

```bash
bin/rails test test/controllers/dashboards_controller_test.rb
bin/rails test
```

- [ ] **Step 5: Commit**

```bash
git add app/controllers/dashboards_controller.rb test/controllers/dashboards_controller_test.rb
git commit -m "perf: parallelize dashboard service calls, fix OpenStruct → Struct, fix double MepRate call, scope rescue"
```

---

## Phase 4 — Code Health

---

### Task 10: Dead Code Removal

**Files:**
- Modify: `app/services/exchanges/bingx_client.rb`
- Modify: `app/services/exchanges/binance_client.rb`
- Modify: `app/models/spot_account.rb`
- Delete: `app/javascript/controllers/hello_controller.js`
- Delete: `app/jobs/historic_sync_job.rb`
- Modify: `app/jobs/stocks/weekly_snapshot_job.rb` → replaced by `take_snapshot_job.rb`
- Delete: `app/jobs/stocks/monthly_snapshot_job.rb`
- Create: `app/jobs/stocks/take_snapshot_job.rb`
- Modify: `config/recurring.yml` or wherever the jobs are scheduled (search for weekly/monthly schedule)

- [ ] **Step 1: Remove BingxClient debug methods and alias**

In `app/services/exchanges/bingx_client.rb`:

Remove lines 38–64 (the 5 `debug_*` methods) and line 105 (`alias stablequote_pair? allowed_quote?`).

Update `self.ping` to inline the fills fetch directly:

```ruby
def self.ping(api_key:, api_secret:)
  client = new(api_key: api_key, api_secret: api_secret)
  client.signed_get(SWAP_FILL_ORDERS_PATH, "startTime" => 1.day.ago.to_i * 1000, "limit" => 1)
  true
rescue => e
  Rails.logger.warn("[BingxClient] Ping failed: #{e.message}")
  false
end
```

Replace `stablequote_pair?` with `allowed_quote?` in the two private methods that use it:
- `fetch_trades_from_v2_fills` line: `trades << normalized if normalized && stablequote_pair?(normalized[:symbol])`
- `fetch_trades_from_income` line: same pattern

Change both to `allowed_quote?`.

- [ ] **Step 2: Remove BASE_URL_TESTNET from both clients**

In `app/services/exchanges/bingx_client.rb`, remove line 8:
```ruby
BASE_URL_TESTNET = "https://open-api-vst.bingx.com"
```

In `app/services/exchanges/binance_client.rb`, remove line 15:
```ruby
BASE_URL_TESTNET = "https://testnet.binancefuture.com"
```

- [ ] **Step 3: Remove SpotAccount.default_for class method**

In `app/models/spot_account.rb`, remove lines 14–16:
```ruby
def self.default_for(user)
  user.spot_accounts.find_by(default: true) || user.spot_accounts.first
end
```

- [ ] **Step 4: Delete hello_controller.js**

```bash
rm app/javascript/controllers/hello_controller.js
```

Verify it's not referenced anywhere:
```bash
grep -r "hello" app/javascript/ app/views/
```

- [ ] **Step 5: Delete HistoricSyncJob**

Confirm no call sites outside the admin controller:
```bash
grep -rn "HistoricSyncJob" app/ config/
```

Expected: only in the job file itself and possibly in tests. The controller uses `SyncExchangeAccountJob` directly.

```bash
rm app/jobs/historic_sync_job.rb
```

Delete any corresponding test file if it exists:
```bash
rm -f test/jobs/historic_sync_job_test.rb
```

- [ ] **Step 6: Merge WeeklySnapshotJob + MonthlySnapshotJob into TakeSnapshotJob**

Create the merged job:

```ruby
# app/jobs/stocks/take_snapshot_job.rb
# frozen_string_literal: true

module Stocks
  # Takes a portfolio snapshot for every stock portfolio with a given source label.
  # Replaces Stocks::WeeklySnapshotJob and Stocks::MonthlySnapshotJob.
  # Schedule via config/recurring.yml:
  #   stocks_weekly_snapshot:  cron: "0 0 * * MON"  class: "Stocks::TakeSnapshotJob"  args: ["weekly"]
  #   stocks_monthly_snapshot: cron: "0 0 1 * *"    class: "Stocks::TakeSnapshotJob"  args: ["monthly"]
  class TakeSnapshotJob < ApplicationJob
    queue_as :default

    def perform(source)
      StockPortfolio.find_each do |portfolio|
        Stocks::PortfolioSnapshotService.call(stock_portfolio: portfolio, source: source)
      rescue => e
        Rails.logger.error("[Stocks::TakeSnapshotJob] Portfolio #{portfolio.id} source=#{source}: #{e.message}")
      end
    end
  end
end
```

- [ ] **Step 7: Find and update the recurring job schedule**

```bash
grep -rn "WeeklySnapshotJob\|MonthlySnapshotJob" config/
```

Update any scheduler config (likely `config/recurring.yml` or similar) to reference `Stocks::TakeSnapshotJob` with the appropriate `args: ["weekly"]` / `args: ["monthly"]`.

- [ ] **Step 8: Delete the old snapshot jobs**

```bash
rm app/jobs/stocks/weekly_snapshot_job.rb
rm app/jobs/stocks/monthly_snapshot_job.rb
```

- [ ] **Step 9: Run tests**

```bash
bin/rails test
```

- [ ] **Step 10: Commit**

```bash
git add -A
git commit -m "chore: remove dead code — BingX debug methods, BASE_URL_TESTNET, SpotAccount.default_for, hello_controller, HistoricSyncJob; merge snapshot jobs into TakeSnapshotJob"
```

---

### Task 11: Extract HasSingleDefault Concern

**Files:**
- Create: `app/models/concerns/has_single_default.rb`
- Modify: `app/models/portfolio.rb`
- Modify: `app/models/spot_account.rb`
- Modify: `app/models/stock_portfolio.rb`
- Test: `test/models/concerns/has_single_default_test.rb` (create)

- [ ] **Step 1: Write test for the concern**

```ruby
# test/models/concerns/has_single_default_test.rb
require "test_helper"

class HasSingleDefaultTest < ActiveSupport::TestCase
  # Use Portfolio as the test subject since it includes the concern
  setup do
    @user = users(:one)
    @user.portfolios.delete_all
  end

  test "saving a portfolio as default clears other defaults for the same user" do
    p1 = @user.portfolios.create!(name: "P1", start_date: Date.today, default: true)
    p2 = @user.portfolios.create!(name: "P2", start_date: Date.today, default: false)

    p2.update!(default: true)

    assert_equal false, p1.reload.default
    assert_equal true, p2.reload.default
  end

  test "non-default save does not clear other defaults" do
    p1 = @user.portfolios.create!(name: "P1", start_date: Date.today, default: true)
    p2 = @user.portfolios.create!(name: "P2", start_date: Date.today, default: false)

    p2.update!(name: "P2 updated")

    assert_equal true, p1.reload.default
  end
end
```

- [ ] **Step 2: Run the test to confirm it passes with current code (it should)**

```bash
bin/rails test test/models/concerns/has_single_default_test.rb
```

This verifies the existing behavior before refactoring.

- [ ] **Step 3: Create the concern**

```ruby
# app/models/concerns/has_single_default.rb
# frozen_string_literal: true

module HasSingleDefault
  extend ActiveSupport::Concern

  included do
    before_save :clear_other_defaults, if: :default?
  end

  private

  def clear_other_defaults
    self.class.where(user_id: user_id).where.not(id: id).update_all(default: false)
  end
end
```

- [ ] **Step 4: Update Portfolio to use the concern**

In `app/models/portfolio.rb`:

1. Add `include HasSingleDefault` after the class opening line (before the `belongs_to` lines)
2. Remove the `before_save :clear_other_defaults, if: :default?` line
3. Remove the entire `clear_other_defaults` private method (lines 44–47)

Result (relevant diff):
```ruby
class Portfolio < ApplicationRecord
  include HasSingleDefault

  belongs_to :user
  # ... rest unchanged, without the before_save and private method
```

- [ ] **Step 5: Update SpotAccount to use the concern**

In `app/models/spot_account.rb`:

1. Add `include HasSingleDefault` after `belongs_to :allocation_bucket, optional: true`
2. Remove `before_save :clear_other_defaults, if: :default?`
3. Remove the `clear_other_defaults` private method (lines 41–44)

- [ ] **Step 6: Update StockPortfolio to use the concern**

In `app/models/stock_portfolio.rb`:

1. Add `include HasSingleDefault` after the class opening (before `belongs_to`)
2. Remove `before_save :clear_other_defaults, if: :default?`
3. Remove the `clear_other_defaults` private method (lines 33–35)

- [ ] **Step 7: Run tests**

```bash
bin/rails test test/models/concerns/has_single_default_test.rb
bin/rails test
```

- [ ] **Step 8: Commit**

```bash
git add app/models/concerns/has_single_default.rb app/models/portfolio.rb app/models/spot_account.rb app/models/stock_portfolio.rb test/models/concerns/has_single_default_test.rb
git commit -m "refactor: extract HasSingleDefault concern — remove clear_other_defaults duplication across 3 models"
```

---

### Task 12: Fix rgba Color Bug in Dashboard Charts

**Files:**
- Modify: `app/javascript/controllers/dashboard_charts_controller.js`

**Context:** Line 90 does `color.replace("rgb", "rgba").replace(")", ", 0.1)")` where `color` is `"rgb(5 150 105)"` (CSS Color Level 4 space-separated syntax). The result `"rgba(5 150 105, 0.1)"` is invalid — `rgba()` uses comma-separated values. Chart.js silently uses a transparent fill.

- [ ] **Step 1: Fix the color string in renderPlChart**

In `app/javascript/controllers/dashboard_charts_controller.js`, replace line 90:

```javascript
// Before (invalid CSS — space-separated rgb with rgba):
backgroundColor: color.replace("rgb", "rgba").replace(")", ", 0.1)"),

// After (parse space-separated rgb, produce valid rgba):
backgroundColor: color.replace(/^rgb\((\d+)\s+(\d+)\s+(\d+)\)$/, "rgba($1, $2, $3, 0.1)"),
```

- [ ] **Step 2: Fix the hardcoded invalid rgba in renderBalanceChart**

In `renderBalanceChart` (around line 68–69), the balance chart uses a hardcoded invalid string:

```javascript
// Before:
backgroundColor: "rgba(15 23 42, 0.1)",

// After:
backgroundColor: "rgba(15, 23, 42, 0.1)",
```

- [ ] **Step 3: Verify in browser**

```bash
./bin/dev
```

Open the dashboard. Open DevTools → Console. Confirm no color-related errors. The P&L chart area should now show a tinted fill (green or red at 10% opacity) instead of transparent.

- [ ] **Step 4: Commit**

```bash
git add app/javascript/controllers/dashboard_charts_controller.js
git commit -m "fix: correct invalid rgba() color strings in dashboard charts — space-separated rgb is not valid rgba"
```

---

## Self-Review Checklist

**Spec coverage:**

| Brainstorm item | Task |
|---|---|
| Session fixation (`reset_session`) | Task 1 |
| Login rate limiting | Task 2 |
| Hardcoded encryption key fallbacks | Task 3 |
| CSP + Permissions Policy | Task 4 |
| Mobile navigation (hamburger drawer) | Task 5 |
| `Stocks::CurrentPriceFetcher` cache + parallel | Task 6 |
| `Spot::CurrentPriceFetcher` cache | Task 7 |
| Allocation N CoinGecko calls → 1 | Task 8 |
| Dashboard sequential → parallel + OpenStruct fix | Task 9 |
| Dead code removal | Task 10 |
| `HasSingleDefault` concern | Task 11 |
| rgba chart bug | Task 12 |

All items covered. No placeholders found. No spec gaps.
