# BYOK API Keys Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace all platform-owned API keys (Finnhub, IOL, CoinGecko, Anthropic/Claude) with per-user BYOK storage in a `user_api_keys` table, and migrate the existing Gemini key into the same table.

**Architecture:** A `UserApiKey` model (provider enum + encrypted key + encrypted secret) stores one row per user per provider. Services receive a `user:` param and look up their key via `UserApiKey.key_for(user, :provider)`. Controllers check for missing keys and set `flash.now[:alert]` with a link to the new `Settings::ApiKeysController`.

**Tech Stack:** Rails 8, Active Record Encryption, Tailwind CSS, Minitest

---

## File Map

**New files:**
- `db/migrate/TIMESTAMP_create_user_api_keys.rb`
- `db/migrate/TIMESTAMP_migrate_gemini_key_to_user_api_keys.rb`
- `app/models/user_api_key.rb`
- `app/controllers/settings/api_keys_controller.rb`
- `app/views/settings/api_keys/index.html.erb`
- `test/models/user_api_key_test.rb`
- `test/controllers/settings/api_keys_controller_test.rb`

**Modified files:**
- `app/models/user.rb` — add `has_many :user_api_keys`, `api_key_for` helper; remove `encrypts :gemini_api_key` + gemini helpers
- `app/services/ai/provider_for_user.rb` — read both Anthropic and Gemini from `user_api_keys`
- `app/services/stocks/finnhub_client.rb` — accept `api_key:` param
- `app/services/stocks/current_price_fetcher.rb` — accept `user:` param
- `app/services/stocks/iol_client.rb` — accept `username:, password:` params; fix token cache to use Rails.cache per-credentials
- `app/services/stocks/argentine_current_price_fetcher.rb` — accept `user:` param
- `app/services/exchanges/binance/spot_ticker_fetcher.rb` — accept `api_key:` param
- `app/services/spot/current_price_fetcher.rb` — accept `user:` param
- `app/services/dashboards/summary_service.rb` — pass `user:` to all fetchers
- `app/services/stocks/portfolio_snapshot_service.rb` — pass `user:` to fetchers
- `app/controllers/stocks_controller.rb` — pass `current_user` to fetchers; add flash alerts
- `app/controllers/stocks/valuation_check_controller.rb` — pass `current_user`; add flash alert
- `app/controllers/spot_controller.rb` — pass `current_user`; add flash alert
- `app/controllers/dashboards_controller.rb` — add flash alerts for missing keys
- `app/controllers/settings_controller.rb` — remove `update_ai_key` / `remove_ai_key`
- `app/views/settings/show.html.erb` — remove Gemini card and Claude platform card; add link to API keys page
- `config/routes.rb` — add `namespace :settings { resources :api_keys }`; remove old AI key routes
- `test/services/stocks/current_price_fetcher_test.rb` — update for new signature
- `test/services/stocks/argentine_current_price_fetcher_test.rb` — update for new signature
- `test/services/spot/current_price_fetcher_test.rb` — update for new signature
- `test/controllers/settings_controller_test.rb` — remove old AI key action tests

---

## Task 1: UserApiKey model + migration

**Files:**
- Create: `db/migrate/TIMESTAMP_create_user_api_keys.rb`
- Create: `app/models/user_api_key.rb`
- Modify: `app/models/user.rb`
- Create: `test/models/user_api_key_test.rb`

- [ ] **Step 1: Generate the migration**

```bash
bin/rails generate migration CreateUserApiKeys
```

- [ ] **Step 2: Fill in the migration**

Open the generated file and replace its content with:

```ruby
class CreateUserApiKeys < ActiveRecord::Migration[8.0]
  def change
    create_table :user_api_keys do |t|
      t.references :user, null: false, foreign_key: true
      t.string :provider, null: false
      t.text :key
      t.text :secret
      t.timestamps
    end

    add_index :user_api_keys, [:user_id, :provider], unique: true
  end
end
```

- [ ] **Step 3: Run the migration**

```bash
bin/rails db:migrate
```

Expected: migration runs with no errors. `db/schema.rb` now contains `user_api_keys` table.

- [ ] **Step 4: Write the failing model test**

Create `test/models/user_api_key_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class UserApiKeyTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
  end

  test "key_for returns key string when row exists" do
    @user.user_api_keys.create!(provider: "finnhub", key: "abc123")
    assert_equal "abc123", UserApiKey.key_for(@user, :finnhub)
  end

  test "key_for returns nil when no row" do
    assert_nil UserApiKey.key_for(@user, :finnhub)
  end

  test "credentials_for returns hash with key and secret" do
    @user.user_api_keys.create!(provider: "iol", key: "user@example.com", secret: "pass")
    result = UserApiKey.credentials_for(@user, :iol)
    assert_equal "user@example.com", result[:key]
    assert_equal "pass", result[:secret]
  end

  test "credentials_for returns nil when no row" do
    assert_nil UserApiKey.credentials_for(@user, :iol)
  end

  test "api_key_for on user returns the row" do
    row = @user.user_api_keys.create!(provider: "coingecko", key: "cg_key")
    assert_equal row, @user.api_key_for(:coingecko)
  end

  test "api_key_for returns nil when not configured" do
    assert_nil @user.api_key_for(:coingecko)
  end

  test "provider uniqueness per user" do
    @user.user_api_keys.create!(provider: "finnhub", key: "first")
    duplicate = @user.user_api_keys.build(provider: "finnhub", key: "second")
    assert_not duplicate.valid?
  end

  test "key is encrypted at rest" do
    row = @user.user_api_keys.create!(provider: "finnhub", key: "secret_key")
    raw = ActiveRecord::Base.connection.select_value(
      "SELECT key FROM user_api_keys WHERE id = #{row.id}"
    )
    assert_not_equal "secret_key", raw
  end
end
```

- [ ] **Step 5: Run the test to verify it fails**

```bash
bin/rails test test/models/user_api_key_test.rb
```

Expected: errors like `uninitialized constant UserApiKey`

- [ ] **Step 6: Create the model**

Create `app/models/user_api_key.rb`:

```ruby
# frozen_string_literal: true

class UserApiKey < ApplicationRecord
  PROVIDERS = %w[finnhub coingecko iol anthropic gemini].freeze

  belongs_to :user

  encrypts :key
  encrypts :secret

  validates :provider, inclusion: { in: PROVIDERS }
  validates :provider, uniqueness: { scope: :user_id }
  validates :key, presence: true

  def self.key_for(user, provider)
    user.user_api_keys.find_by(provider: provider.to_s)&.key
  end

  def self.credentials_for(user, provider)
    row = user.user_api_keys.find_by(provider: provider.to_s)
    row ? { key: row.key, secret: row.secret } : nil
  end
end
```

- [ ] **Step 7: Add association and helper to User**

In `app/models/user.rb`, add after the existing `has_many` lines:

```ruby
has_many :user_api_keys, dependent: :destroy
```

Add the instance helper before `def default_portfolio`:

```ruby
def api_key_for(provider)
  user_api_keys.find_by(provider: provider.to_s)
end
```

- [ ] **Step 8: Run tests to verify they pass**

```bash
bin/rails test test/models/user_api_key_test.rb
```

Expected: all 8 tests pass.

- [ ] **Step 9: Commit**

```bash
git add db/migrate/*_create_user_api_keys.rb db/schema.rb app/models/user_api_key.rb app/models/user.rb test/models/user_api_key_test.rb
git commit -m "feat: add UserApiKey model with encrypted key/secret storage"
```

---

## Task 2: Migrate Gemini key into UserApiKey

**Files:**
- Create: `db/migrate/TIMESTAMP_migrate_gemini_key_to_user_api_keys.rb`
- Modify: `app/models/user.rb`
- Modify: `app/services/ai/provider_for_user.rb`

- [ ] **Step 1: Generate the data + schema migration**

```bash
bin/rails generate migration MigrateGeminiKeyToUserApiKeys
```

- [ ] **Step 2: Fill in the migration**

```ruby
class MigrateGeminiKeyToUserApiKeys < ActiveRecord::Migration[8.0]
  def up
    User.find_each do |user|
      next if user.gemini_api_key.blank?
      UserApiKey.find_or_create_by!(user: user, provider: "gemini") do |r|
        r.key = user.gemini_api_key
      end
    end

    remove_column :users, :gemini_api_key
  end

  def down
    add_column :users, :gemini_api_key, :text
  end
end
```

- [ ] **Step 3: Run migration**

```bash
bin/rails db:migrate
```

Expected: `gemini_api_key` column gone from `users`, any existing Gemini keys moved to `user_api_keys`.

- [ ] **Step 4: Write failing test for ProviderForUser**

In `test/services/ai/provider_for_user_test.rb` (create if missing), add:

```ruby
# frozen_string_literal: true

require "test_helper"

module Ai
  class ProviderForUserTest < ActiveSupport::TestCase
    setup do
      @user = users(:one)
    end

    test "uses user anthropic key when configured" do
      @user.user_api_keys.create!(provider: "anthropic", key: "sk-ant-test")
      provider = ProviderForUser.new(@user)
      assert provider.claude?
      assert_not provider.gemini?
      assert provider.configured?
    end

    test "falls back to gemini key when no anthropic key" do
      @user.user_api_keys.create!(provider: "gemini", key: "AIza-test")
      provider = ProviderForUser.new(@user)
      assert_not provider.claude?
      assert provider.gemini?
      assert provider.configured?
    end

    test "not configured when neither key present" do
      provider = ProviderForUser.new(@user)
      assert_not provider.configured?
      assert_nil provider.client
    end

    test "anthropic takes priority over gemini" do
      @user.user_api_keys.create!(provider: "anthropic", key: "sk-ant-test")
      @user.user_api_keys.create!(provider: "gemini", key: "AIza-test")
      provider = ProviderForUser.new(@user)
      assert provider.claude?
      assert_not provider.gemini?
    end
  end
end
```

- [ ] **Step 5: Run to see it fail**

```bash
bin/rails test test/services/ai/provider_for_user_test.rb
```

Expected: failures because `ProviderForUser` still reads `@user.gemini_api_key` (column gone) and `credentials.dig(:anthropic)`.

- [ ] **Step 6: Update ProviderForUser**

Replace `app/services/ai/provider_for_user.rb` with:

```ruby
# frozen_string_literal: true

module Ai
  # Returns the appropriate AI client for a user based on their stored BYOK keys.
  #
  # Resolution order:
  #   1. User's own Anthropic key → ClaudeService (deep analysis, web search)
  #   2. User's own Gemini key → GeminiService (standard analysis)
  #   3. Neither configured → nil
  class ProviderForUser
    def initialize(user)
      @user = user
    end

    def client
      if anthropic_api_key.present?
        Ai::ClaudeService.new(api_key: anthropic_api_key)
      elsif gemini_api_key.present?
        Ai::GeminiService.new(api_key: gemini_api_key)
      end
    end

    def claude?
      anthropic_api_key.present?
    end

    def gemini?
      !claude? && gemini_api_key.present?
    end

    def configured?
      claude? || gemini?
    end

    private

    def anthropic_api_key
      @anthropic_api_key ||= UserApiKey.key_for(@user, :anthropic)
    end

    def gemini_api_key
      @gemini_api_key ||= UserApiKey.key_for(@user, :gemini)
    end
  end
end
```

- [ ] **Step 7: Remove gemini-specific methods from User**

In `app/models/user.rb`, remove:
- `encrypts :gemini_api_key`
- `def gemini_api_key_configured?`
- `def gemini_api_key_masked`

- [ ] **Step 8: Run tests**

```bash
bin/rails test test/services/ai/provider_for_user_test.rb
```

Expected: all 4 tests pass.

- [ ] **Step 9: Run full test suite to catch breakage**

```bash
bin/rails test
```

Fix any failures from removed `gemini_api_key` references.

- [ ] **Step 10: Commit**

```bash
git add db/migrate/*_migrate_gemini_key_to_user_api_keys.rb db/schema.rb app/models/user.rb app/services/ai/provider_for_user.rb test/services/ai/provider_for_user_test.rb
git commit -m "feat: migrate gemini_api_key to user_api_keys; ProviderForUser reads from BYOK table"
```

---

## Task 3: Settings::ApiKeysController + unified API keys UI

**Files:**
- Create: `app/controllers/settings/api_keys_controller.rb`
- Create: `app/views/settings/api_keys/index.html.erb`
- Modify: `config/routes.rb`
- Modify: `app/controllers/settings_controller.rb`
- Modify: `app/views/settings/show.html.erb`
- Create: `test/controllers/settings/api_keys_controller_test.rb`

- [ ] **Step 1: Write failing controller tests**

Create `test/controllers/settings/api_keys_controller_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

module Settings
  class ApiKeysControllerTest < ActionDispatch::IntegrationTest
    setup do
      @user = users(:one)
      post login_path, params: { email: @user.email, password: "password" }
    end

    test "index lists all providers" do
      get settings_api_keys_path
      assert_response :success
      assert_select "body", /Finnhub/
      assert_select "body", /CoinGecko/
      assert_select "body", /IOL/
      assert_select "body", /Anthropic/
      assert_select "body", /Gemini/
    end

    test "upsert creates a key" do
      assert_difference "UserApiKey.count" do
        post upsert_settings_api_keys_path, params: { provider: "finnhub", key: "abc123" }
      end
      assert_redirected_to settings_api_keys_path
      assert_equal "abc123", UserApiKey.key_for(@user, :finnhub)
    end

    test "upsert updates existing key" do
      @user.user_api_keys.create!(provider: "finnhub", key: "old")
      assert_no_difference "UserApiKey.count" do
        post upsert_settings_api_keys_path, params: { provider: "finnhub", key: "new" }
      end
      assert_equal "new", UserApiKey.key_for(@user, :finnhub)
    end

    test "upsert stores key and secret for iol" do
      post upsert_settings_api_keys_path, params: { provider: "iol", key: "user@example.com", secret: "pass" }
      creds = UserApiKey.credentials_for(@user, :iol)
      assert_equal "user@example.com", creds[:key]
      assert_equal "pass", creds[:secret]
    end

    test "upsert rejects blank key" do
      assert_no_difference "UserApiKey.count" do
        post upsert_settings_api_keys_path, params: { provider: "finnhub", key: "" }
      end
      assert_redirected_to settings_api_keys_path
    end

    test "destroy removes the key" do
      @user.user_api_keys.create!(provider: "finnhub", key: "abc")
      assert_difference "UserApiKey.count", -1 do
        delete settings_api_key_path("finnhub")
      end
      assert_redirected_to settings_api_keys_path
    end

    test "destroy for unknown provider does not raise" do
      delete settings_api_key_path("finnhub")
      assert_redirected_to settings_api_keys_path
    end
  end
end
```

- [ ] **Step 2: Run to verify they fail**

```bash
bin/rails test test/controllers/settings/api_keys_controller_test.rb
```

Expected: routing errors (routes don't exist yet).

- [ ] **Step 3: Add routes**

In `config/routes.rb`, replace:

```ruby
resource :settings, only: %i[show update], controller: "settings"
patch  "settings/ai_key", to: "settings#update_ai_key", as: :settings_ai_key
delete "settings/ai_key", to: "settings#remove_ai_key",  as: :remove_settings_ai_key
```

with:

```ruby
resource :settings, only: %i[show update], controller: "settings"
namespace :settings do
  resources :api_keys, only: %i[index destroy], param: :provider do
    collection { post :upsert }
  end
end
```

- [ ] **Step 4: Create the controller**

Create `app/controllers/settings/api_keys_controller.rb`:

```ruby
# frozen_string_literal: true

module Settings
  class ApiKeysController < ApplicationController
    PROVIDERS = UserApiKey::PROVIDERS.freeze

    def index
      @keys_by_provider = current_user.user_api_keys.index_by(&:provider)
    end

    def upsert
      provider = params[:provider].to_s
      key      = params[:key].to_s.strip
      secret   = params[:secret].to_s.strip.presence

      unless PROVIDERS.include?(provider) && key.present?
        redirect_to settings_api_keys_path, alert: "Invalid provider or blank key." and return
      end

      row = current_user.user_api_keys.find_or_initialize_by(provider: provider)
      row.key    = key
      row.secret = secret

      if row.save
        redirect_to settings_api_keys_path, notice: "#{provider.capitalize} key saved."
      else
        redirect_to settings_api_keys_path, alert: "Could not save key."
      end
    end

    def destroy
      current_user.user_api_keys.find_by(provider: params[:provider])&.destroy
      redirect_to settings_api_keys_path, notice: "Key removed."
    end
  end
end
```

- [ ] **Step 5: Create the view directory**

```bash
mkdir -p app/views/settings/api_keys
```

- [ ] **Step 6: Create the index view**

Create `app/views/settings/api_keys/index.html.erb`:

```erb
<div class="mx-auto max-w-4xl">
  <div class="mb-6">
    <h1 class="mb-1 text-2xl font-semibold text-slate-900">API Keys</h1>
    <p class="text-sm text-slate-600">Your keys are stored encrypted and never shared. Each key is used only for your account.</p>
  </div>

  <div class="space-y-4">
    <%# Finnhub %>
    <%= render "settings/api_keys/provider_card",
      provider: "finnhub",
      label: "Finnhub",
      description: "Used to fetch real-time US stock prices.",
      link_text: "Get a free key at finnhub.io",
      link_url: "https://finnhub.io/dashboard",
      row: @keys_by_provider["finnhub"],
      fields: [{ name: :key, placeholder: "pk_live_..." }] %>

    <%# CoinGecko %>
    <%= render "settings/api_keys/provider_card",
      provider: "coingecko",
      label: "CoinGecko",
      description: "Used to fetch crypto spot prices.",
      link_text: "Get a demo key at coingecko.com",
      link_url: "https://www.coingecko.com/en/developers/dashboard",
      row: @keys_by_provider["coingecko"],
      fields: [{ name: :key, placeholder: "CG-..." }] %>

    <%# IOL %>
    <%= render "settings/api_keys/provider_card",
      provider: "iol",
      label: "InvertirOnline (IOL)",
      description: "Used to fetch Argentine CEDEAR prices in ARS.",
      link_text: "Sign up at invertironline.com",
      link_url: "https://www.invertironline.com",
      row: @keys_by_provider["iol"],
      fields: [
        { name: :key, placeholder: "your@email.com", label: "Username (email)" },
        { name: :secret, placeholder: "••••••••", label: "Password", type: "password" }
      ] %>

    <%# Anthropic %>
    <%= render "settings/api_keys/provider_card",
      provider: "anthropic",
      label: "Anthropic (Claude)",
      description: "Enables deep stock analysis with live web search.",
      link_text: "Get an API key at console.anthropic.com",
      link_url: "https://console.anthropic.com",
      row: @keys_by_provider["anthropic"],
      fields: [{ name: :key, placeholder: "sk-ant-..." }] %>

    <%# Gemini %>
    <%= render "settings/api_keys/provider_card",
      provider: "gemini",
      label: "Google Gemini",
      description: "Enables AI-powered portfolio analysis.",
      link_text: "Get a free key at aistudio.google.com",
      link_url: "https://aistudio.google.com/app/apikey",
      row: @keys_by_provider["gemini"],
      fields: [{ name: :key, placeholder: "AIza..." }] %>
  </div>
</div>
```

- [ ] **Step 7: Create the provider card partial**

Create `app/views/settings/api_keys/_provider_card.html.erb`:

```erb
<div class="rounded-lg border border-slate-200 bg-white overflow-hidden">
  <div class="flex items-center justify-between px-4 py-3 border-b border-slate-100">
    <span class="text-sm font-semibold text-slate-800"><%= label %></span>
    <% if row %>
      <span class="inline-flex items-center gap-1.5 text-xs font-medium text-emerald-700">
        <span class="h-1.5 w-1.5 rounded-full bg-emerald-500"></span>
        Configured
      </span>
    <% else %>
      <span class="text-xs text-slate-400">Not configured</span>
    <% end %>
  </div>

  <div class="px-4 py-4 space-y-3">
    <p class="text-sm text-slate-600">
      <%= description %>
      <a href="<%= link_url %>" target="_blank" rel="noopener noreferrer" class="text-slate-800 underline underline-offset-2 hover:text-slate-600"><%= link_text %></a>
    </p>

    <% if row %>
      <div class="flex items-center gap-3">
        <span class="flex-1 rounded-md bg-slate-50 border border-slate-200 px-3 py-2 text-sm font-mono text-slate-700">
          <%= row.key.present? && row.key.length >= 8 ? "#{row.key[0..3]}...#{row.key[-4..]}" : "••••••••" %>
        </span>
        <%= button_to "Remove", settings_api_key_path(provider), method: :delete,
          class: "px-3 py-1.5 text-sm text-red-600 hover:text-red-700 hover:bg-red-50 rounded-md transition-colors" %>
      </div>
    <% else %>
      <%= form_with url: upsert_settings_api_keys_path, method: :post do |f| %>
        <%= f.hidden_field :provider, value: provider %>
        <div class="space-y-2">
          <% fields.each do |field| %>
            <div>
              <% if field[:label] %>
                <label class="block text-xs font-medium text-slate-600 mb-1"><%= field[:label] %></label>
              <% end %>
              <%= f.text_field field[:name],
                placeholder: field[:placeholder],
                type: field.fetch(:type, "text"),
                autocomplete: "off",
                class: "w-full rounded-md border border-slate-300 px-3 py-2 text-sm text-slate-800 placeholder-slate-400 focus:outline-none focus:ring-2 focus:ring-slate-500 focus:border-transparent" %>
            </div>
          <% end %>
        </div>
        <%= f.submit "Save", class: "mt-2 px-4 py-2 text-sm bg-slate-800 text-white rounded-md hover:bg-slate-700 focus:outline-none focus:ring-2 focus:ring-slate-500" %>
        <p class="text-xs text-slate-400">Stored encrypted. Never shared.</p>
      <% end %>
    <% end %>
  </div>
</div>
```

- [ ] **Step 8: Remove old Gemini/Claude sections from settings/show.html.erb**

In `app/views/settings/show.html.erb`, remove everything after the `<hr>` tag (the two AI card divs). Replace with:

```erb
<hr class="border-slate-200">

<div class="rounded-lg border border-slate-200 bg-white px-4 py-4 flex items-center justify-between">
  <div>
    <p class="text-sm font-semibold text-slate-800">API Keys</p>
    <p class="text-sm text-slate-500">Configure your Finnhub, CoinGecko, IOL, Anthropic, and Gemini keys.</p>
  </div>
  <%= link_to "Manage API Keys", settings_api_keys_path, class: "shrink-0 px-4 py-2 text-sm bg-slate-800 text-white rounded-md hover:bg-slate-700" %>
</div>
```

- [ ] **Step 9: Remove old AI key actions from SettingsController**

In `app/controllers/settings_controller.rb`, remove `update_ai_key` and `remove_ai_key` methods entirely. File should be:

```ruby
# frozen_string_literal: true

class SettingsController < ApplicationController
  def show
    @ai_provider = Ai::ProviderForUser.new(current_user)
  end

  def update
    if current_user.update(settings_params)
      redirect_to settings_path, notice: "Settings saved."
    else
      render :show, status: :unprocessable_entity
    end
  end

  private

  def settings_params
    params.require(:user).permit(:sync_interval)
  end
end
```

- [ ] **Step 10: Run the controller tests**

```bash
bin/rails test test/controllers/settings/api_keys_controller_test.rb
```

Expected: all tests pass.

- [ ] **Step 11: Run full test suite**

```bash
bin/rails test
```

Fix any failures from removed routes or methods.

- [ ] **Step 12: Commit**

```bash
git add config/routes.rb app/controllers/settings/ app/views/settings/ app/controllers/settings_controller.rb test/controllers/settings/
git commit -m "feat: add Settings::ApiKeysController and unified API keys settings page"
```

---

## Task 4: Finnhub BYOK

**Files:**
- Modify: `app/services/stocks/finnhub_client.rb`
- Modify: `app/services/stocks/current_price_fetcher.rb`
- Modify: `app/controllers/stocks_controller.rb`
- Modify: `app/controllers/stocks/valuation_check_controller.rb`
- Modify: `app/services/stocks/portfolio_snapshot_service.rb`
- Modify: `app/services/dashboards/summary_service.rb`
- Modify: `test/services/stocks/current_price_fetcher_test.rb`

- [ ] **Step 1: Write failing tests for CurrentPriceFetcher**

Replace `test/services/stocks/current_price_fetcher_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

module Stocks
  class CurrentPriceFetcherTest < ActiveSupport::TestCase
    setup do
      Rails.cache.clear
      @user = users(:one)
    end

    test "returns empty hash for blank tickers" do
      assert_equal({}, CurrentPriceFetcher.call(tickers: [], user: @user))
    end

    test "returns empty hash when no finnhub key configured" do
      assert_equal({}, CurrentPriceFetcher.call(tickers: ["AAPL"], user: @user))
    end

    test "returns prices for valid tickers" do
      @user.user_api_keys.create!(provider: "finnhub", key: "test_key")
      stub_client = stub_finnhub("AAPL" => BigDecimal("180.0"))
      CurrentPriceFetcher.stub(:build_client, stub_client) do
        result = CurrentPriceFetcher.call(tickers: ["AAPL"], user: @user)
        assert_equal BigDecimal("180.0"), result["AAPL"]
      end
    end

    test "caches results for 5 minutes" do
      @user.user_api_keys.create!(provider: "finnhub", key: "test_key")
      call_count = 0
      stub_client = Object.new
      stub_client.define_singleton_method(:quote) { |_| call_count += 1; BigDecimal("180.0") }
      CurrentPriceFetcher.stub(:build_client, stub_client) do
        CurrentPriceFetcher.call(tickers: ["AAPL"], user: @user)
        CurrentPriceFetcher.call(tickers: ["AAPL"], user: @user)
      end
      assert_equal 1, call_count
    end

    test "omits tickers with nil price" do
      @user.user_api_keys.create!(provider: "finnhub", key: "test_key")
      stub_client = Object.new
      stub_client.define_singleton_method(:quote) { |_| nil }
      CurrentPriceFetcher.stub(:build_client, stub_client) do
        assert_equal({}, CurrentPriceFetcher.call(tickers: ["UNKNOWN"], user: @user))
      end
    end

    private

    def stub_finnhub(prices_by_ticker)
      stub_client = Object.new
      stub_client.define_singleton_method(:quote) { |ticker| prices_by_ticker[ticker] }
      stub_client
    end
  end
end
```

- [ ] **Step 2: Run to verify failures**

```bash
bin/rails test test/services/stocks/current_price_fetcher_test.rb
```

Expected: argument errors (missing `user:` param).

- [ ] **Step 3: Update FinnhubClient to accept api_key param**

Replace `app/services/stocks/finnhub_client.rb`:

```ruby
# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

module Stocks
  class FinnhubClient
    BASE_URL = "https://finnhub.io/api/v1"

    def initialize(api_key:)
      @api_key = api_key
    end

    def quote(ticker)
      return nil if @api_key.blank?

      uri = URI("#{BASE_URL}/quote")
      uri.query = URI.encode_www_form(symbol: ticker, token: @api_key)
      response = Net::HTTP.get_response(uri)
      return nil unless response.is_a?(Net::HTTPSuccess)

      data = JSON.parse(response.body)
      price = data["c"]&.to_d
      price&.positive? ? price : nil
    rescue => e
      Rails.logger.error("[Stocks::FinnhubClient] Error fetching quote for #{ticker}: #{e.message}")
      nil
    end
  end
end
```

- [ ] **Step 4: Update CurrentPriceFetcher**

Replace `app/services/stocks/current_price_fetcher.rb`:

```ruby
# frozen_string_literal: true

module Stocks
  # Fetches current prices for a list of stock tickers via Finnhub.
  # Requires the user to have a Finnhub API key configured in user_api_keys.
  # Returns Hash ticker => BigDecimal; missing tickers or missing key returns {}.
  class CurrentPriceFetcher
    def self.call(tickers:, user:)
      new(tickers: tickers, user: user).call
    end

    def self.build_client(api_key)
      FinnhubClient.new(api_key: api_key)
    end

    def initialize(tickers:, user:)
      @tickers = tickers.to_a.map { |t| t.to_s.strip.upcase }.reject(&:blank?).uniq
      @api_key = UserApiKey.key_for(user, :finnhub)
    end

    def call
      return {} if @tickers.empty?
      return {} if @api_key.blank?

      client = self.class.build_client(@api_key)
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

- [ ] **Step 5: Run service tests**

```bash
bin/rails test test/services/stocks/current_price_fetcher_test.rb
```

Expected: all pass.

- [ ] **Step 6: Update StocksController**

In `app/controllers/stocks_controller.rb`, find the line:

```ruby
current_prices = Stocks::CurrentPriceFetcher.call(tickers: open_tickers)
```

Replace with:

```ruby
unless current_user.api_key_for(:finnhub)
  flash.now[:alert] = "Stock prices require a Finnhub API key. #{view_context.link_to('Configure it here', settings_api_keys_path, class: 'underline')}".html_safe
end
current_prices = Stocks::CurrentPriceFetcher.call(tickers: open_tickers, user: current_user)
```

- [ ] **Step 7: Update ValuationCheckController**

In `app/controllers/stocks/valuation_check_controller.rb`, find:

```ruby
prices = Stocks::CurrentPriceFetcher.call(tickers: [@ticker])
```

Replace with:

```ruby
unless current_user.api_key_for(:finnhub)
  flash.now[:alert] = "Stock prices require a Finnhub API key. #{view_context.link_to('Configure it here', settings_api_keys_path, class: 'underline')}".html_safe
end
prices = Stocks::CurrentPriceFetcher.call(tickers: [@ticker], user: current_user)
```

- [ ] **Step 8: Update PortfolioSnapshotService**

In `app/services/stocks/portfolio_snapshot_service.rb`, find:

```ruby
Stocks::CurrentPriceFetcher.call(tickers: tickers)
```

Replace with:

```ruby
Stocks::CurrentPriceFetcher.call(tickers: tickers, user: @stock_portfolio.user)
```

- [ ] **Step 9: Update DashboardsSummaryService**

In `app/services/dashboards/summary_service.rb`, find (inside `stocks_summary`):

```ruby
current_prices = Stocks::CurrentPriceFetcher.call(tickers: open_tickers)
```

Replace with:

```ruby
current_prices = Stocks::CurrentPriceFetcher.call(tickers: open_tickers, user: @user)
```

- [ ] **Step 10: Run full test suite**

```bash
bin/rails test
```

Fix any argument errors from the signature change.

- [ ] **Step 11: Commit**

```bash
git add app/services/stocks/finnhub_client.rb app/services/stocks/current_price_fetcher.rb app/controllers/stocks_controller.rb app/controllers/stocks/valuation_check_controller.rb app/services/stocks/portfolio_snapshot_service.rb app/services/dashboards/summary_service.rb test/services/stocks/current_price_fetcher_test.rb
git commit -m "feat: Finnhub BYOK — read key from user_api_keys, flash alert when missing"
```

---

## Task 5: IOL BYOK

**Files:**
- Modify: `app/services/stocks/iol_client.rb`
- Modify: `app/services/stocks/argentine_current_price_fetcher.rb`
- Modify: `app/controllers/stocks_controller.rb`
- Modify: `app/services/stocks/portfolio_snapshot_service.rb`
- Modify: `app/services/dashboards/summary_service.rb`
- Modify: `test/services/stocks/argentine_current_price_fetcher_test.rb`

- [ ] **Step 1: Write failing tests for ArgentineCurrentPriceFetcher**

Replace `test/services/stocks/argentine_current_price_fetcher_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

module Stocks
  class ArgentineCurrentPriceFetcherTest < ActiveSupport::TestCase
    setup do
      Rails.cache.clear
      @user = users(:one)
    end

    test "returns empty hash for blank tickers" do
      assert_equal({}, ArgentineCurrentPriceFetcher.call(tickers: [], user: @user))
    end

    test "returns empty hash when no IOL credentials configured" do
      assert_equal({}, ArgentineCurrentPriceFetcher.call(tickers: ["AAPL"], user: @user))
    end

    test "returns prices when credentials configured" do
      @user.user_api_keys.create!(provider: "iol", key: "user@example.com", secret: "pass")
      stub_client = Object.new
      stub_client.define_singleton_method(:quote) { |ticker| ticker == "AAPL" ? BigDecimal("1500.0") : nil }
      ArgentineCurrentPriceFetcher.stub(:build_client, stub_client) do
        result = ArgentineCurrentPriceFetcher.call(tickers: ["AAPL"], user: @user)
        assert_equal BigDecimal("1500.0"), result["AAPL"]
      end
    end

    test "omits tickers with nil price" do
      @user.user_api_keys.create!(provider: "iol", key: "user@example.com", secret: "pass")
      stub_client = Object.new
      stub_client.define_singleton_method(:quote) { |_| nil }
      ArgentineCurrentPriceFetcher.stub(:build_client, stub_client) do
        assert_equal({}, ArgentineCurrentPriceFetcher.call(tickers: ["UNKNOWN"], user: @user))
      end
    end
  end
end
```

- [ ] **Step 2: Run to verify failures**

```bash
bin/rails test test/services/stocks/argentine_current_price_fetcher_test.rb
```

Expected: argument errors.

- [ ] **Step 3: Update IolClient**

Replace `app/services/stocks/iol_client.rb`:

```ruby
# frozen_string_literal: true

require "net/http"
require "uri"
require "json"
require "digest"

module Stocks
  # Fetches CEDEAR/stock quotes from InvertirOnline (IOL) API.
  # Auth: POST /token with username+password → bearer token (15 min validity).
  # Token is cached in Rails.cache per credential pair for 14 minutes.
  class IolClient
    TOKEN_URL = "https://api.invertironline.com/token"
    BASE_URL  = "https://api.invertironline.com/api/v2"
    MARKET    = "bCBA"

    def initialize(username:, password:)
      @username = username
      @password = password
    end

    # Returns BigDecimal ARS price or nil — never raises.
    def quote(ticker)
      token = fetch_token
      return nil if token.blank?

      uri = URI("#{BASE_URL}/#{MARKET}/Titulos/#{URI.encode_uri_component(ticker)}/Cotizacion")
      request = Net::HTTP::Get.new(uri)
      request["Authorization"] = "Bearer #{token}"

      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(request) }
      return nil unless response.is_a?(Net::HTTPSuccess)

      data = JSON.parse(response.body)
      price = data["ultimoPrecio"]&.to_d
      price&.positive? ? price : nil
    rescue => e
      Rails.logger.error("[Stocks::IolClient] quote(#{ticker}) error: #{e.message}")
      nil
    end

    private

    def fetch_token
      cache_key = "iol_token:#{Digest::SHA256.hexdigest("#{@username}:#{@password}")}"
      Rails.cache.fetch(cache_key, expires_in: 14.minutes) do
        response = Net::HTTP.post(
          URI(TOKEN_URL),
          URI.encode_www_form(username: @username, password: @password, grant_type: "password"),
          "Content-Type" => "application/x-www-form-urlencoded"
        )
        return nil unless response.is_a?(Net::HTTPSuccess)

        data = JSON.parse(response.body)
        data["access_token"].presence
      end
    rescue => e
      Rails.logger.error("[Stocks::IolClient] token fetch error: #{e.message}")
      nil
    end
  end
end
```

- [ ] **Step 4: Update ArgentineCurrentPriceFetcher**

Replace `app/services/stocks/argentine_current_price_fetcher.rb`:

```ruby
# frozen_string_literal: true

module Stocks
  # Fetches current CEDEAR prices in ARS from InvertirOnline (IOL).
  # Requires the user to have IOL credentials configured in user_api_keys.
  # Returns Hash<ticker, BigDecimal>; empty when credentials are missing.
  class ArgentineCurrentPriceFetcher
    def self.call(tickers:, user:)
      new(tickers: tickers, user: user).call
    end

    def self.build_client(username:, password:)
      Stocks::IolClient.new(username: username, password: password)
    end

    def initialize(tickers:, user:)
      @tickers = tickers.to_a.map { |t| t.to_s.strip.upcase }.reject(&:blank?).uniq
      @creds   = UserApiKey.credentials_for(user, :iol)
    end

    def call
      return {} if @tickers.empty?
      return {} if @creds.nil?

      client = self.class.build_client(username: @creds[:key], password: @creds[:secret])
      mutex  = Mutex.new
      prices = {}

      threads = @tickers.map do |ticker|
        Thread.new do
          price = Rails.cache.fetch("iol_price:#{ticker}", expires_in: 5.minutes, skip_nil: true) do
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

- [ ] **Step 5: Update StocksController for IOL flash alert**

In `app/controllers/stocks_controller.rb`, find the Argentine branch:

```ruby
prices_thread = Thread.new { Stocks::ArgentineCurrentPriceFetcher.call(tickers: open_tickers) }
```

Replace with:

```ruby
unless current_user.api_key_for(:iol)
  flash.now[:alert] = "Argentine stock prices require IOL credentials. #{view_context.link_to('Configure them here', settings_api_keys_path, class: 'underline')}".html_safe
end
prices_thread = Thread.new { Stocks::ArgentineCurrentPriceFetcher.call(tickers: open_tickers, user: current_user) }
```

Also find the non-threaded call (if any) and add `user: current_user`.

- [ ] **Step 6: Update PortfolioSnapshotService for IOL**

In `app/services/stocks/portfolio_snapshot_service.rb`, find:

```ruby
Stocks::ArgentineCurrentPriceFetcher.call(tickers: tickers)
```

Replace with:

```ruby
Stocks::ArgentineCurrentPriceFetcher.call(tickers: tickers, user: @stock_portfolio.user)
```

- [ ] **Step 7: Update DashboardsSummaryService for IOL**

In `app/services/dashboards/summary_service.rb`, find (inside `stocks_summary`):

```ruby
current_prices = Stocks::ArgentineCurrentPriceFetcher.call(tickers: open_tickers)
```

Replace with:

```ruby
current_prices = Stocks::ArgentineCurrentPriceFetcher.call(tickers: open_tickers, user: @user)
```

- [ ] **Step 8: Run tests**

```bash
bin/rails test test/services/stocks/argentine_current_price_fetcher_test.rb
bin/rails test
```

Fix any failures.

- [ ] **Step 9: Commit**

```bash
git add app/services/stocks/iol_client.rb app/services/stocks/argentine_current_price_fetcher.rb app/controllers/stocks_controller.rb app/services/stocks/portfolio_snapshot_service.rb app/services/dashboards/summary_service.rb test/services/stocks/argentine_current_price_fetcher_test.rb
git commit -m "feat: IOL BYOK — read credentials from user_api_keys, per-user token cache"
```

---

## Task 6: CoinGecko BYOK

**Files:**
- Modify: `app/services/exchanges/binance/spot_ticker_fetcher.rb`
- Modify: `app/services/spot/current_price_fetcher.rb`
- Modify: `app/controllers/spot_controller.rb`
- Modify: `app/controllers/dashboards_controller.rb`
- Modify: `app/services/dashboards/summary_service.rb`
- Modify: `test/services/spot/current_price_fetcher_test.rb`

- [ ] **Step 1: Write failing tests for Spot::CurrentPriceFetcher**

Replace `test/services/spot/current_price_fetcher_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

module Spot
  class CurrentPriceFetcherTest < ActiveSupport::TestCase
    setup do
      Rails.cache.clear
      @user = users(:one)
    end

    test "returns empty hash for blank tokens" do
      assert_equal({}, CurrentPriceFetcher.call(tokens: [], user: @user))
    end

    test "returns prices when fetcher succeeds" do
      prices = { "BTC" => BigDecimal("60000") }
      Exchanges::Binance::SpotTickerFetcher.stub(:fetch_prices, prices) do
        result = CurrentPriceFetcher.call(tokens: ["BTC"], user: @user)
        assert_equal BigDecimal("60000"), result["BTC"]
      end
    end

    test "caches results" do
      call_count = 0
      stub_fetcher = Object.new
      stub_fetcher.define_singleton_method(:fetch_prices) { |**| call_count += 1; { "BTC" => BigDecimal("60000") } }
      Exchanges::Binance::SpotTickerFetcher.stub(:new, stub_fetcher) do
        CurrentPriceFetcher.call(tokens: ["BTC"], user: @user)
        CurrentPriceFetcher.call(tokens: ["BTC"], user: @user)
      end
      assert_equal 1, call_count
    end

    test "normalizes and deduplicates tokens" do
      call_count = 0
      stub_fetcher = Object.new
      stub_fetcher.define_singleton_method(:fetch_prices) { |**| call_count += 1; {} }
      Exchanges::Binance::SpotTickerFetcher.stub(:new, stub_fetcher) do
        CurrentPriceFetcher.call(tokens: ["btc", "BTC", "Btc"], user: @user)
      end
      assert_equal 1, call_count
    end
  end
end
```

- [ ] **Step 2: Run to verify failures**

```bash
bin/rails test test/services/spot/current_price_fetcher_test.rb
```

Expected: argument errors.

- [ ] **Step 3: Update SpotTickerFetcher to accept api_key param**

In `app/services/exchanges/binance/spot_ticker_fetcher.rb`, update the class method and constructor:

```ruby
def self.fetch_prices(tokens:, api_key: nil)
  new(api_key: api_key).fetch_prices(tokens: tokens)
end

def initialize(api_key: nil)
  @api_key = api_key
end
```

In the `fetch_prices` instance method, replace:

```ruby
req["x-cg-demo-api-key"] = ENV["COINGECKO_API_KEY"] if ENV["COINGECKO_API_KEY"].present?
```

with:

```ruby
req["x-cg-demo-api-key"] = @api_key if @api_key.present?
```

- [ ] **Step 4: Update Spot::CurrentPriceFetcher**

Replace `app/services/spot/current_price_fetcher.rb`:

```ruby
# frozen_string_literal: true

module Spot
  # Fetches current spot prices for a list of tokens via CoinGecko.
  # Uses the user's CoinGecko API key if configured; works without one (free tier rate limits apply).
  # Results are cached for 2 minutes keyed on the sorted token list.
  class CurrentPriceFetcher
    def self.call(tokens:, user:)
      new(tokens: tokens, user: user).call
    end

    def initialize(tokens:, user:)
      @tokens  = tokens.to_a.map { |t| t.to_s.strip.upcase }.reject(&:blank?).uniq
      @api_key = UserApiKey.key_for(user, :coingecko)
    end

    def call
      return {} if @tokens.empty?

      cache_key = "spot_prices:#{@tokens.sort.join(',')}"
      Rails.cache.fetch(cache_key, expires_in: 2.minutes) do
        Exchanges::Binance::SpotTickerFetcher.fetch_prices(tokens: @tokens, api_key: @api_key)
      end
    end
  end
end
```

- [ ] **Step 5: Update SpotController**

In `app/controllers/spot_controller.rb`, find:

```ruby
prices = Spot::CurrentPriceFetcher.call(tokens: open_tokens)
```

Replace with:

```ruby
unless current_user.api_key_for(:coingecko)
  flash.now[:alert] = "Crypto prices require a CoinGecko API key. #{view_context.link_to('Configure it here', settings_api_keys_path, class: 'underline')}".html_safe
end
prices = Spot::CurrentPriceFetcher.call(tokens: open_tokens, user: current_user)
```

- [ ] **Step 6: Update DashboardsSummaryService for CoinGecko**

In `app/services/dashboards/summary_service.rb`, find (inside `spot_summary`):

```ruby
current_prices = Spot::CurrentPriceFetcher.call(tokens: open_tokens)
```

Replace with:

```ruby
current_prices = Spot::CurrentPriceFetcher.call(tokens: open_tokens, user: @user)
```

- [ ] **Step 7: Add flash alert to DashboardsController**

In `app/controllers/dashboards_controller.rb`, inside the `show` action (or equivalent), add before the service call:

```ruby
unless current_user.api_key_for(:coingecko)
  flash.now[:alert] = "Crypto spot prices require a CoinGecko API key. #{view_context.link_to('Configure it here', settings_api_keys_path, class: 'underline')}".html_safe
end
```

- [ ] **Step 8: Run tests**

```bash
bin/rails test test/services/spot/current_price_fetcher_test.rb
bin/rails test
```

Fix any failures.

- [ ] **Step 9: Commit**

```bash
git add app/services/exchanges/binance/spot_ticker_fetcher.rb app/services/spot/current_price_fetcher.rb app/controllers/spot_controller.rb app/controllers/dashboards_controller.rb app/services/dashboards/summary_service.rb test/services/spot/current_price_fetcher_test.rb
git commit -m "feat: CoinGecko BYOK — read key from user_api_keys, pass to SpotTickerFetcher"
```

---

## Task 7: Remove deprecated code and env var references

**Files:**
- Modify: `config/routes.rb` — already done in Task 3 (verify old AI routes are gone)
- Modify: `app/services/stocks/iol_client.rb` — class-level token cache already removed in Task 5
- Verify no remaining ENV references for the migrated keys

- [ ] **Step 1: Search for remaining ENV references**

```bash
grep -rn "FINNHUB_API_KEY\|IOL_USERNAME\|IOL_PASSWORD\|COINGECKO_API_KEY" app/ config/
```

Expected: no matches (all removed in Tasks 4–6).

- [ ] **Step 2: Search for remaining credentials references**

```bash
grep -rn "credentials.dig.*finnhub\|credentials.dig.*iol\|credentials.dig.*anthropic\|credentials.dig.*gemini" app/
```

Expected: no matches.

- [ ] **Step 3: Search for gemini_api_key references**

```bash
grep -rn "gemini_api_key\|gemini_api_key_configured\|gemini_api_key_masked" app/ test/
```

Fix any remaining references.

- [ ] **Step 4: Search for old AI key route helpers**

```bash
grep -rn "settings_ai_key\|remove_settings_ai_key" app/ test/
```

Fix any remaining references.

- [ ] **Step 5: Run full test suite one final time**

```bash
bin/rails test
```

Expected: all tests pass with no failures.

- [ ] **Step 6: Final commit**

```bash
git add -A
git commit -m "chore: remove deprecated env var and credentials references for migrated API keys"
```
