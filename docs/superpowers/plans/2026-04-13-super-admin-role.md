# Super Admin Role Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the `admin` boolean with a three-tier `role` enum (`user`, `admin`, `super_admin`), add a dedicated admin management section to the admin panel, and enforce role-based access control for role-change actions.

**Architecture:** Migration backfills `role` from the existing `admin` boolean then drops it. The `User` model gains a Rails enum with predicate helpers. `Admin::BaseController` gains a `require_super_admin` guard. A new `Admin::AdminsController` mirrors `StudentsController`. Two new view templates and minor updates to existing ones complete the UI.

**Tech Stack:** Rails 8, PostgreSQL, Minitest, Tailwind CSS, Hotwire/Turbo

---

## File Map

| File | Action |
|---|---|
| `db/migrate/TIMESTAMP_add_role_to_users.rb` | Create — adds `role` column, backfills, drops `admin` |
| `test/fixtures/users.yml` | Modify — swap `admin:` for `role:`, add `super_admin` fixture |
| `app/models/user.rb` | Modify — add `enum :role`, replace guard callback |
| `test/models/user_test.rb` | Modify — update old tests, add enum + guard tests |
| `app/models/admin/student_stats.rb` | Modify — `where(admin: false)` → `where(role: "user")` |
| `app/controllers/admin/base_controller.rb` | Modify — update `require_admin`, add `require_super_admin` |
| `test/controllers/admin/base_controller_test.rb` | Modify — update + add super_admin access tests |
| `app/controllers/admin/students_controller.rb` | Modify — scope to `role: "user"`, add `promote` action |
| `test/controllers/admin/students_controller_test.rb` | Modify — update scope test, add `promote` tests |
| `config/routes.rb` | Modify — add `promote` route, add `admins` resource |
| `app/controllers/admin/admins_controller.rb` | Create — `index`, `show`, `toggle_active`, `demote` |
| `test/controllers/admin/admins_controller_test.rb` | Create — full test coverage |
| `app/views/admin/students/index.html.erb` | Modify — add Promote button |
| `app/views/admin/students/show.html.erb` | Modify — add Promote to Admin button |
| `app/views/admin/admins/index.html.erb` | Create — admins list |
| `app/views/admin/admins/show.html.erb` | Create — admin detail |
| `app/views/layouts/admin.html.erb` | Modify — add Admins nav link |
| `app/controllers/admin/dashboard_controller.rb` | Modify — `where(admin: false)` → `where(role: "user")` |

---

## Task 1: Database Migration

**Files:**
- Create: `db/migrate/TIMESTAMP_add_role_to_users.rb`

- [ ] **Step 1: Generate the migration**

```bash
bin/rails generate migration AddRoleToUsers
```

- [ ] **Step 2: Write the migration body**

Open the generated file and replace its body with:

```ruby
class AddRoleToUsers < ActiveRecord::Migration[8.0]
  def up
    add_column :users, :role, :string, null: false, default: "user"
    execute "UPDATE users SET role = 'admin' WHERE admin = true"
    remove_column :users, :admin
  end

  def down
    add_column :users, :admin, :boolean, null: false, default: false
    execute "UPDATE users SET admin = true WHERE role IN ('admin', 'super_admin')"
    remove_column :users, :role
  end
end
```

- [ ] **Step 3: Run the migration**

```bash
bin/rails db:migrate
```

Expected output ends with: `== AddRoleToUsers: migrated`

- [ ] **Step 4: Commit**

```bash
git add db/migrate db/schema.rb
git commit -m "feat: add role column to users, backfill from admin boolean, drop admin column"
```

---

## Task 2: Update Fixtures

**Files:**
- Modify: `test/fixtures/users.yml`

Fixtures must match the new schema before any tests can run.

- [ ] **Step 1: Replace the fixture file**

Replace the entire contents of `test/fixtures/users.yml` with:

```yaml
one:
  email: one@example.com
  password_digest: MyString
  sync_interval: daily
  active: true
  role: user

two:
  email: two@example.com
  password_digest: MyString
  sync_interval: daily
  active: true
  role: user

admin:
  email: admin@example.com
  password_digest: MyString
  active: true
  role: admin

super_admin:
  email: super_admin@example.com
  password_digest: MyString
  active: true
  role: super_admin

inactive:
  email: inactive@example.com
  password_digest: MyString
  active: false
  role: user
```

- [ ] **Step 2: Commit**

```bash
git add test/fixtures/users.yml
git commit -m "test: update user fixtures to use role column"
```

---

## Task 3: Update User Model

**Files:**
- Modify: `app/models/user.rb`
- Modify: `test/models/user_test.rb`

- [ ] **Step 1: Write failing tests**

Replace the entire contents of `test/models/user_test.rb` with:

```ruby
# frozen_string_literal: true

require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "role defaults to user" do
    user = User.new(email: "test@example.com", password: "password")
    assert_predicate user, :user?
  end

  test "active defaults to true" do
    user = User.new(email: "test@example.com", password: "password")
    assert_equal true, user.active
  end

  test "email is normalized to lowercase on save" do
    user = User.create!(email: "Test@EXAMPLE.COM", password: "password", password_confirmation: "password")
    assert_equal "test@example.com", user.email
  end

  test "email strips whitespace on save" do
    user = User.create!(email: "  test2@example.com  ", password: "password", password_confirmation: "password")
    assert_equal "test2@example.com", user.email
  end

  test "active scope returns only active users" do
    active_user = users(:one)
    inactive_user = users(:inactive)
    scoped = User.active
    assert_includes scoped, active_user
    assert_not_includes scoped, inactive_user
  end

  test "admin? returns true for admin role" do
    assert_predicate users(:admin), :admin?
  end

  test "super_admin? returns true for super_admin role" do
    assert_predicate users(:super_admin), :super_admin?
  end

  test "last active super_admin cannot be deactivated" do
    super_admin = users(:super_admin)
    super_admin.update!(password: "password", password_confirmation: "password")

    result = super_admin.update(active: false)
    assert_not result
    assert_includes super_admin.errors[:active], "cannot deactivate the last active super admin"
    assert_predicate super_admin.reload, :active?
  end

  test "super_admin can be deactivated when another active super_admin exists" do
    super_admin = users(:super_admin)
    super_admin.update!(password: "password", password_confirmation: "password")

    second = User.create!(email: "second_sa@example.com", password: "password",
                          password_confirmation: "password", role: "super_admin", active: true)

    result = super_admin.update(active: false)
    assert result, "Should allow deactivating when another active super_admin exists"
    assert_not super_admin.reload.active?
  ensure
    second.destroy
    super_admin.update_columns(active: true)
  end

  test "admin can be deactivated freely" do
    admin = users(:admin)
    admin.update!(password: "password", password_confirmation: "password")

    result = admin.update(active: false)
    assert result, "Admins should be deactivatable regardless of other admins"
  ensure
    admin.update_columns(active: true)
  end

  test "gemini_api_key_configured? returns false when key is nil" do
    user = User.new(email: "ai@example.com", password: "password")
    assert_equal false, user.gemini_api_key_configured?
  end

  test "gemini_api_key_configured? returns true when key is set" do
    user = users(:one)
    user.gemini_api_key = "AIzaSyTestKey12345678"
    assert_equal true, user.gemini_api_key_configured?
  end

  test "gemini_api_key_masked returns nil when key is blank" do
    user = User.new(email: "ai@example.com", password: "password")
    assert_nil user.gemini_api_key_masked
  end

  test "gemini_api_key_masked returns masked string when key is set" do
    user = users(:one)
    user.gemini_api_key = "AIzaSyTestKey12345678"
    assert_equal "AIza...5678", user.gemini_api_key_masked
  end

  test "generates a password reset token" do
    user = users(:one)
    user.update!(password: "password")
    token = user.generate_token_for(:password_reset)
    assert_not_nil token
    assert_equal user, User.find_by_token_for(:password_reset, token)
  end

  test "password reset token expires after 2 hours" do
    user = users(:one)
    user.update!(password: "password")
    token = user.generate_token_for(:password_reset)

    travel 2.hours + 1.second do
      assert_nil User.find_by_token_for(:password_reset, token)
    end
  end

  test "password reset token is invalidated after password change" do
    user = users(:one)
    user.update!(password: "oldpassword")
    token = user.generate_token_for(:password_reset)

    user.update!(password: "newpassword", password_confirmation: "newpassword")
    assert_nil User.find_by_token_for(:password_reset, token)
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
bin/rails test test/models/user_test.rb
```

Expected: multiple failures — `undefined method 'user?'`, `undefined method 'super_admin?'`, wrong error message for deactivation guard.

- [ ] **Step 3: Update the User model**

Replace the entire contents of `app/models/user.rb` with:

```ruby
class User < ApplicationRecord
  has_secure_password

  encrypts :gemini_api_key

  generates_token_for :password_reset, expires_in: 2.hours do
    password_digest.last(10)
  end

  SYNC_INTERVALS = %w[hourly daily twice_daily].freeze

  enum :role, { user: "user", admin: "admin", super_admin: "super_admin" }, default: "user"

  before_validation { self.email = email.to_s.strip.downcase }
  before_update :prevent_last_super_admin_deactivation

  validates :email, presence: true, uniqueness: true
  validates :sync_interval, inclusion: { in: SYNC_INTERVALS }, allow_nil: true
  validates :active, inclusion: { in: [ true, false ] }

  scope :active, -> { where(active: true) }

  has_many :exchange_accounts, dependent: :destroy
  has_many :trades, through: :exchange_accounts
  has_many :portfolios, dependent: :destroy
  has_many :spot_accounts, dependent: :destroy
  has_many :stock_portfolios, dependent: :destroy
  has_many :user_preferences, dependent: :destroy
  has_many :cedear_instruments, dependent: :destroy
  has_many :watchlist_tickers, dependent: :destroy
  has_many :allocation_buckets, dependent: :destroy
  has_many :allocation_manual_entries, dependent: :destroy

  def default_portfolio
    portfolios.find_by(default: true)
  end

  def gemini_api_key_configured?
    gemini_api_key.present?
  end

  def gemini_api_key_masked
    return nil unless gemini_api_key.present? && gemini_api_key.length >= 8
    "#{gemini_api_key[0..3]}...#{gemini_api_key[-4..]}"
  end

  private

  def prevent_last_super_admin_deactivation
    return unless super_admin? && will_save_change_to_active?(to: false)

    remaining = User.where(role: "super_admin", active: true).where.not(id: id).count
    if remaining.zero?
      errors.add(:active, "cannot deactivate the last active super admin")
      throw :abort
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
bin/rails test test/models/user_test.rb
```

Expected: all green.

- [ ] **Step 5: Commit**

```bash
git add app/models/user.rb test/models/user_test.rb
git commit -m "feat: replace admin boolean with role enum, guard last super_admin deactivation"
```

---

## Task 4: Update Admin::StudentStats

**Files:**
- Modify: `app/models/admin/student_stats.rb`

- [ ] **Step 1: Update the module**

Replace the entire contents of `app/models/admin/student_stats.rb` with:

```ruby
# frozen_string_literal: true

module Admin
  module StudentStats
    # Returns { user_id (int) => realized_pl (float) } for all non-admin students.
    # Students with no closed positions are absent from the hash (treat as 0.0 at call site).
    def self.realized_pl_by_user
      Position
        .joins(exchange_account: :user)
        .where(open: false)
        .where(users: { role: "user" })
        .group("users.id")
        .sum(:net_pl)
        .transform_values(&:to_f)
    end

    # Returns array of { user_id:, email:, realized_pl:, active: } sorted by descending P&L.
    # Uses pluck to avoid loading full User objects into memory.
    def self.leaderboard(pl_by_user)
      User.where(role: "user")
          .pluck(:id, :email, :active)
          .map { |id, email, active| { user_id: id, email: email, realized_pl: pl_by_user.fetch(id, 0.0), active: active } }
          .sort_by { |r| -r[:realized_pl] }
    end

    # Returns { true => open_count, false => closed_count } for a given student.
    def self.position_counts_for(user)
      Position.for_student(user)
              .group(:open)
              .count
    end
  end
end
```

- [ ] **Step 2: Run existing admin tests to verify nothing broke**

```bash
bin/rails test test/controllers/admin/
```

Expected: all green.

- [ ] **Step 3: Commit**

```bash
git add app/models/admin/student_stats.rb
git commit -m "fix: update StudentStats queries to use role column instead of admin boolean"
```

---

## Task 5: Update Admin::BaseController

**Files:**
- Modify: `app/controllers/admin/base_controller.rb`
- Modify: `test/controllers/admin/base_controller_test.rb`

- [ ] **Step 1: Write failing tests**

Replace the entire contents of `test/controllers/admin/base_controller_test.rb` with:

```ruby
# frozen_string_literal: true

require "test_helper"

class Admin::BaseControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:admin)
    @admin.update!(password: "password", password_confirmation: "password")

    @super_admin = users(:super_admin)
    @super_admin.update!(password: "password", password_confirmation: "password")

    @student = users(:one)
    @student.update!(password: "password", password_confirmation: "password")
  end

  test "admin can access admin dashboard" do
    post login_url, params: { email: @admin.email, password: "password" }
    get admin_root_url
    assert_response :success
  end

  test "super_admin can access admin dashboard" do
    post login_url, params: { email: @super_admin.email, password: "password" }
    get admin_root_url
    assert_response :success
  end

  test "non-admin student is redirected from admin routes" do
    post login_url, params: { email: @student.email, password: "password" }
    get admin_root_url
    assert_redirected_to root_url
    assert_match "Not authorized", flash[:alert]
  end

  test "unauthenticated user is redirected to login from admin routes" do
    get admin_root_url
    assert_redirected_to login_url
  end

  test "inactive admin cannot access admin routes" do
    @admin.update_columns(active: false)
    post login_url, params: { email: @admin.email, password: "password" }

    get admin_root_url
    assert_redirected_to login_url
  ensure
    @admin.update_columns(active: true)
  end
end
```

- [ ] **Step 2: Run tests to verify relevant ones pass already, super_admin test fails**

```bash
bin/rails test test/controllers/admin/base_controller_test.rb
```

Expected: `super_admin can access admin dashboard` fails (super_admin is blocked since `require_admin` only checks `admin?` currently).

- [ ] **Step 3: Update BaseController**

Replace the entire contents of `app/controllers/admin/base_controller.rb` with:

```ruby
# frozen_string_literal: true

class Admin::BaseController < ApplicationController
  layout "admin"
  before_action :require_admin

  private

  def require_admin
    redirect_to root_path, alert: "Not authorized." and return unless current_user&.admin? || current_user&.super_admin?
  end

  def require_super_admin
    redirect_to root_path, alert: "Not authorized." and return unless current_user&.super_admin?
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
bin/rails test test/controllers/admin/base_controller_test.rb
```

Expected: all green.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/admin/base_controller.rb test/controllers/admin/base_controller_test.rb
git commit -m "feat: update require_admin to allow super_admin, add require_super_admin guard"
```

---

## Task 6: Update Routes

**Files:**
- Modify: `config/routes.rb`

- [ ] **Step 1: Update the admin namespace**

In `config/routes.rb`, replace the admin namespace block (lines 69–75) with:

```ruby
namespace :admin do
  root "dashboard#show"
  resources :students, only: %i[index show] do
    member do
      patch :toggle_active
      patch :promote
    end
  end
  resources :admins, only: %i[index show] do
    member do
      patch :toggle_active
      patch :demote
    end
  end
  resource :invite_code, only: %i[show create], controller: "invite_code"
end
```

- [ ] **Step 2: Verify routes are correct**

```bash
bin/rails routes | grep admin
```

Expected output includes:
```
promote_admin_student  PATCH  /admin/students/:id/promote
toggle_active_admin_admin  PATCH  /admin/admins/:id/toggle_active
demote_admin_admin  PATCH  /admin/admins/:id/demote
```

- [ ] **Step 3: Commit**

```bash
git add config/routes.rb
git commit -m "feat: add promote route to students, add admins resource with toggle_active and demote"
```

---

## Task 7: Update Admin::StudentsController

**Files:**
- Modify: `app/controllers/admin/students_controller.rb`
- Modify: `test/controllers/admin/students_controller_test.rb`

- [ ] **Step 1: Write failing tests**

Replace the entire contents of `test/controllers/admin/students_controller_test.rb` with:

```ruby
# frozen_string_literal: true

require "test_helper"

class Admin::StudentsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:admin)
    @admin.update!(password: "password", password_confirmation: "password")
    post login_url, params: { email: @admin.email, password: "password" }

    @student = users(:one)
  end

  test "index lists role=user students" do
    get admin_students_url
    assert_response :success
  end

  test "show renders student detail" do
    get admin_student_url(@student)
    assert_response :success
  end

  test "toggle_active deactivates an active student" do
    assert @student.active?
    patch toggle_active_admin_student_url(@student)
    assert_redirected_to admin_students_url
    assert_not @student.reload.active?
  ensure
    @student.update_columns(active: true)
  end

  test "toggle_active activates an inactive student" do
    @student.update_columns(active: false)
    patch toggle_active_admin_student_url(@student)
    assert_redirected_to admin_students_url
    assert @student.reload.active?
  end

  test "set_student scopes to role=user only" do
    get admin_student_url(users(:admin))
    assert_response :not_found
  end

  test "promote sets student role to admin" do
    patch promote_admin_student_url(@student)
    assert_redirected_to admin_students_url
    assert_equal "admin", @student.reload.role
  ensure
    @student.update_columns(role: "user")
  end

  test "super_admin can also promote students" do
    super_admin = users(:super_admin)
    super_admin.update!(password: "password", password_confirmation: "password")
    post login_url, params: { email: super_admin.email, password: "password" }

    other_student = users(:two)
    patch promote_admin_student_url(other_student)
    assert_redirected_to admin_students_url
    assert_equal "admin", other_student.reload.role
  ensure
    users(:two).update_columns(role: "user")
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
bin/rails test test/controllers/admin/students_controller_test.rb
```

Expected: `promote` tests fail with routing or action errors.

- [ ] **Step 3: Update StudentsController**

Replace the entire contents of `app/controllers/admin/students_controller.rb` with:

```ruby
# frozen_string_literal: true

class Admin::StudentsController < Admin::BaseController
  before_action :set_student, only: %i[show toggle_active promote]

  def index
    @students   = User.where(role: "user").order(:email).pluck(:id, :email, :active)
    @pl_by_user = Admin::StudentStats.realized_pl_by_user
  end

  def show
    @realized_pl      = Admin::StudentStats.realized_pl_by_user[@student.id].to_f
    @position_counts  = Admin::StudentStats.position_counts_for(@student)
    @recent_positions = Position.for_student(@student)
                                .where(open: false)
                                .order(close_at: :desc)
                                .limit(10)
                                .includes(:exchange_account)
    @stock_portfolios = @student.stock_portfolios.includes(:stock_trades)
    @spot_accounts    = @student.spot_accounts.includes(:spot_transactions)
  end

  def toggle_active
    if @student.update(active: !@student.active)
      redirect_to admin_students_path,
                  notice: "#{@student.email} marked #{@student.active? ? "active" : "inactive"}."
    else
      redirect_to admin_students_path,
                  alert: @student.errors.full_messages.to_sentence
    end
  end

  def promote
    if @student.update(role: "admin")
      redirect_to admin_students_path, notice: "#{@student.email} promoted to admin."
    else
      redirect_to admin_students_path, alert: @student.errors.full_messages.to_sentence
    end
  end

  private

  def set_student
    @student = User.where(role: "user").find(params[:id])
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
bin/rails test test/controllers/admin/students_controller_test.rb
```

Expected: all green.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/admin/students_controller.rb test/controllers/admin/students_controller_test.rb
git commit -m "feat: update StudentsController to scope by role, add promote action"
```

---

## Task 8: Create Admin::AdminsController

**Files:**
- Create: `app/controllers/admin/admins_controller.rb`
- Create: `test/controllers/admin/admins_controller_test.rb`

- [ ] **Step 1: Write failing tests**

Create `test/controllers/admin/admins_controller_test.rb` with:

```ruby
# frozen_string_literal: true

require "test_helper"

class Admin::AdminsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @super_admin = users(:super_admin)
    @super_admin.update!(password: "password", password_confirmation: "password")

    @admin = users(:admin)
    @admin.update!(password: "password", password_confirmation: "password")

    @student = users(:one)
  end

  # ── Access ──────────────────────────────────────────────────────────────────

  test "admin can view admins index" do
    post login_url, params: { email: @admin.email, password: "password" }
    get admin_admins_url
    assert_response :success
  end

  test "super_admin can view admins index" do
    post login_url, params: { email: @super_admin.email, password: "password" }
    get admin_admins_url
    assert_response :success
  end

  test "student cannot access admins index" do
    @student.update!(password: "password", password_confirmation: "password")
    post login_url, params: { email: @student.email, password: "password" }
    get admin_admins_url
    assert_redirected_to root_url
  end

  # ── Show ────────────────────────────────────────────────────────────────────

  test "admin can view admin show page" do
    post login_url, params: { email: @admin.email, password: "password" }
    get admin_admin_url(@admin)
    assert_response :success
  end

  test "set_admin scopes to role=admin only" do
    post login_url, params: { email: @super_admin.email, password: "password" }
    get admin_admin_url(@student)
    assert_response :not_found
  end

  # ── toggle_active (super_admin only) ────────────────────────────────────────

  test "super_admin can toggle_active on an admin" do
    post login_url, params: { email: @super_admin.email, password: "password" }

    assert @admin.active?
    patch toggle_active_admin_admin_url(@admin)
    assert_redirected_to admin_admins_url
    assert_not @admin.reload.active?
  ensure
    @admin.update_columns(active: true)
  end

  test "admin cannot toggle_active on another admin" do
    second_admin = User.create!(email: "second@example.com", password: "password",
                                password_confirmation: "password", role: "admin", active: true)
    post login_url, params: { email: @admin.email, password: "password" }

    patch toggle_active_admin_admin_url(second_admin)
    assert_redirected_to root_url
    assert_match "Not authorized", flash[:alert]
  ensure
    second_admin.destroy
  end

  # ── demote (super_admin only) ────────────────────────────────────────────────

  test "super_admin can demote an admin to user" do
    post login_url, params: { email: @super_admin.email, password: "password" }

    patch demote_admin_admin_url(@admin)
    assert_redirected_to admin_admins_url
    assert_equal "user", @admin.reload.role
  ensure
    @admin.update_columns(role: "admin")
  end

  test "admin cannot demote another admin" do
    second_admin = User.create!(email: "second@example.com", password: "password",
                                password_confirmation: "password", role: "admin", active: true)
    post login_url, params: { email: @admin.email, password: "password" }

    patch demote_admin_admin_url(second_admin)
    assert_redirected_to root_url
    assert_match "Not authorized", flash[:alert]
  ensure
    second_admin.destroy
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
bin/rails test test/controllers/admin/admins_controller_test.rb
```

Expected: failures — uninitialized constant `Admin::AdminsController`.

- [ ] **Step 3: Create AdminsController**

Create `app/controllers/admin/admins_controller.rb` with:

```ruby
# frozen_string_literal: true

class Admin::AdminsController < Admin::BaseController
  before_action :set_admin, only: %i[show toggle_active demote]
  before_action :require_super_admin, only: %i[toggle_active demote]

  def index
    @admins     = User.where(role: "admin").order(:email).pluck(:id, :email, :active)
    @pl_by_user = Admin::StudentStats.realized_pl_by_user
  end

  def show
    @realized_pl      = Admin::StudentStats.realized_pl_by_user[@admin.id].to_f
    @position_counts  = Admin::StudentStats.position_counts_for(@admin)
    @recent_positions = Position.for_student(@admin)
                                .where(open: false)
                                .order(close_at: :desc)
                                .limit(10)
                                .includes(:exchange_account)
    @stock_portfolios = @admin.stock_portfolios.includes(:stock_trades)
    @spot_accounts    = @admin.spot_accounts.includes(:spot_transactions)
  end

  def toggle_active
    if @admin.update(active: !@admin.active)
      redirect_to admin_admins_path,
                  notice: "#{@admin.email} marked #{@admin.active? ? "active" : "inactive"}."
    else
      redirect_to admin_admins_path,
                  alert: @admin.errors.full_messages.to_sentence
    end
  end

  def demote
    if @admin.update(role: "user")
      redirect_to admin_admins_path, notice: "#{@admin.email} demoted to user."
    else
      redirect_to admin_admins_path, alert: @admin.errors.full_messages.to_sentence
    end
  end

  private

  def set_admin
    @admin = User.where(role: "admin").find(params[:id])
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
bin/rails test test/controllers/admin/admins_controller_test.rb
```

Expected: all green.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/admin/admins_controller.rb test/controllers/admin/admins_controller_test.rb
git commit -m "feat: add Admin::AdminsController with index, show, toggle_active, demote"
```

---

## Task 9: Update Students Views

**Files:**
- Modify: `app/views/admin/students/index.html.erb`
- Modify: `app/views/admin/students/show.html.erb`

- [ ] **Step 1: Add Promote button to students index**

Replace the entire contents of `app/views/admin/students/index.html.erb` with:

```erb
<%= render PageHeaderComponent.new(title: "Students") %>

<% if @students.any? %>
  <%= render DataTableComponent.new(columns: [
    { label: "Email",        classes: "text-left" },
    { label: "Realized P&L", classes: "text-right" },
    { label: "Status",       classes: "text-left" },
    { label: "",             classes: "text-right" }
  ]) do |table| %>
    <% @students.each do |id, email, active| %>
      <% pl = @pl_by_user.fetch(id, 0.0) %>
      <% table.with_row do %>
        <td class="whitespace-nowrap px-6 py-4 text-sm font-medium text-slate-900">
          <%= link_to email, admin_student_path(id), class: "hover:text-indigo-600 hover:underline" %>
        </td>
        <td class="whitespace-nowrap px-6 py-4 text-right text-sm font-medium <%= pl >= 0 ? 'text-emerald-600' : 'text-red-600' %>">
          <%= format_money(pl) %>
        </td>
        <td class="whitespace-nowrap px-6 py-4 text-sm">
          <%= render BadgeComponent.new(label: active ? "Active" : "Inactive", variant: active ? :success : :danger) %>
        </td>
        <td class="whitespace-nowrap px-6 py-4 text-right text-sm">
          <%= button_to active ? "Deactivate" : "Activate",
                toggle_active_admin_student_path(id),
                method: :patch,
                class: "text-xs font-medium #{active ? 'text-red-500 hover:text-red-700' : 'text-emerald-600 hover:text-emerald-800'} bg-transparent border-0 p-0 cursor-pointer" %>
          <%= button_to "Promote",
                promote_admin_student_path(id),
                method: :patch,
                class: "ml-4 text-xs font-medium text-indigo-600 hover:text-indigo-800 bg-transparent border-0 p-0 cursor-pointer" %>
          <%= link_to "View", admin_student_path(id), class: "ml-4 text-xs text-slate-500 hover:text-slate-800" %>
        </td>
      <% end %>
    <% end %>
  <% end %>
<% else %>
  <%= render EmptyStateComponent.new(message: "No students registered yet. Share the invite code to get started.") %>
<% end %>
```

- [ ] **Step 2: Add Promote to Admin button to students show**

Replace the entire contents of `app/views/admin/students/show.html.erb` with:

```erb
<%= render PageHeaderComponent.new(title: @student.email, subtitle: "Read-only view") do |c| %>
  <% c.with_actions do %>
    <%= render BadgeComponent.new(label: @student.active? ? "Active" : "Inactive", variant: @student.active? ? :success : :danger) %>
    <%= button_to @student.active? ? "Deactivate" : "Activate",
          toggle_active_admin_student_path(@student),
          method: :patch,
          class: "rounded-md border px-3 py-2 text-sm font-medium focus:outline-none focus:ring-2 focus:ring-slate-500 #{@student.active? ? 'border-red-300 text-red-600 hover:bg-red-50' : 'border-emerald-300 text-emerald-700 hover:bg-emerald-50'}" %>
    <%= button_to "Promote to Admin",
          promote_admin_student_path(@student),
          method: :patch,
          class: "rounded-md border border-indigo-300 px-3 py-2 text-sm font-medium text-indigo-600 hover:bg-indigo-50 focus:outline-none focus:ring-2 focus:ring-indigo-500" %>
    <%= link_to "← All students", admin_students_path, class: "text-sm text-slate-500 hover:text-slate-800" %>
  <% end %>
<% end %>

<%# ── Summary stats ── %>
<% open_count   = @position_counts.fetch(true, 0) %>
<% closed_count = @position_counts.fetch(false, 0) %>
<%= render SummaryStatRowComponent.new(mb: 8) do %>
  <%= render StatCardComponent.new(label: "Realized P&L", value: format_money(@realized_pl), signed: true, color_value: @realized_pl) %>
  <%= render StatCardComponent.new(label: "Open positions", value: open_count) %>
  <%= render StatCardComponent.new(label: "Closed positions", value: closed_count) %>
<% end %>

<%# ── Recent closed positions ── %>
<%= render CardComponent.new(heading: "Recent closed positions", class: "mb-6") do %>
  <% if @recent_positions.any? %>
    <%= render DataTableComponent.new(columns: [
      { label: "Symbol",     classes: "text-left" },
      { label: "Side",       classes: "text-left" },
      { label: "Exchange",   classes: "text-left" },
      { label: "Closed at",  classes: "text-left" },
      { label: "Net P&L",    classes: "text-right" },
      { label: "ROI",        classes: "text-right" }
    ]) do |table| %>
      <% @recent_positions.each do |pos| %>
        <% table.with_row do %>
          <td class="whitespace-nowrap px-6 py-4 text-sm font-medium text-slate-900"><%= pos.symbol %></td>
          <td class="whitespace-nowrap px-6 py-4 text-sm capitalize text-slate-700"><%= pos.position_side %></td>
          <td class="whitespace-nowrap px-6 py-4 text-sm text-slate-500"><%= pos.exchange_account.provider_type.to_s.capitalize %></td>
          <td class="whitespace-nowrap px-6 py-4 text-sm text-slate-500"><%= pos.close_at&.strftime("%b %d, %Y") || "—" %></td>
          <td class="whitespace-nowrap px-6 py-4 text-right text-sm font-medium <%= pos.net_pl.to_d >= 0 ? 'text-emerald-600' : 'text-red-600' %>">
            <%= format_money(pos.net_pl) %>
          </td>
          <td class="whitespace-nowrap px-6 py-4 text-right text-sm <%= pos.roi_percent.to_d >= 0 ? 'text-emerald-600' : 'text-red-600' %>">
            <%= number_to_percentage(pos.roi_percent, precision: 2) %>
          </td>
        <% end %>
      <% end %>
    <% end %>
  <% else %>
    <p class="text-sm text-slate-500">No closed positions yet.</p>
  <% end %>
<% end %>

<%# ── Stock portfolios ── %>
<% if @stock_portfolios.any? %>
  <%= render CardComponent.new(heading: "Stock portfolios", class: "mb-6") do %>
    <div class="space-y-2">
      <% @stock_portfolios.each do |portfolio| %>
        <div class="flex items-center justify-between rounded-md border border-slate-100 px-4 py-3">
          <div>
            <span class="text-sm font-medium text-slate-900"><%= portfolio.name %></span>
            <span class="ml-2 rounded bg-slate-100 px-2 py-0.5 text-xs text-slate-500"><%= portfolio.market %></span>
          </div>
          <span class="text-sm text-slate-500"><%= portfolio.stock_trades.size %> trades</span>
        </div>
      <% end %>
    </div>
  <% end %>
<% end %>

<%# ── Spot accounts ── %>
<% if @spot_accounts.any? %>
  <%= render CardComponent.new(heading: "Spot accounts") do %>
    <div class="space-y-2">
      <% @spot_accounts.each do |account| %>
        <div class="flex items-center justify-between rounded-md border border-slate-100 px-4 py-3">
          <span class="text-sm font-medium text-slate-900"><%= account.name %></span>
          <span class="text-sm text-slate-500"><%= account.spot_transactions.size %> transactions</span>
        </div>
      <% end %>
    </div>
  <% end %>
<% end %>
```

- [ ] **Step 3: Commit**

```bash
git add app/views/admin/students/
git commit -m "feat: add Promote button to students index and show views"
```

---

## Task 10: Create Admins Views

**Files:**
- Create: `app/views/admin/admins/index.html.erb`
- Create: `app/views/admin/admins/show.html.erb`

- [ ] **Step 1: Create the admins directory and index view**

Create `app/views/admin/admins/index.html.erb` with:

```erb
<%= render PageHeaderComponent.new(title: "Admins") %>

<% if @admins.any? %>
  <%= render DataTableComponent.new(columns: [
    { label: "Email",        classes: "text-left" },
    { label: "Realized P&L", classes: "text-right" },
    { label: "Status",       classes: "text-left" },
    { label: "",             classes: "text-right" }
  ]) do |table| %>
    <% @admins.each do |id, email, active| %>
      <% pl = @pl_by_user.fetch(id, 0.0) %>
      <% table.with_row do %>
        <td class="whitespace-nowrap px-6 py-4 text-sm font-medium text-slate-900">
          <%= link_to email, admin_admin_path(id), class: "hover:text-indigo-600 hover:underline" %>
        </td>
        <td class="whitespace-nowrap px-6 py-4 text-right text-sm font-medium <%= pl >= 0 ? 'text-emerald-600' : 'text-red-600' %>">
          <%= format_money(pl) %>
        </td>
        <td class="whitespace-nowrap px-6 py-4 text-sm">
          <%= render BadgeComponent.new(label: active ? "Active" : "Inactive", variant: active ? :success : :danger) %>
        </td>
        <td class="whitespace-nowrap px-6 py-4 text-right text-sm">
          <% if current_user.super_admin? %>
            <%= button_to active ? "Deactivate" : "Activate",
                  toggle_active_admin_admin_path(id),
                  method: :patch,
                  class: "text-xs font-medium #{active ? 'text-red-500 hover:text-red-700' : 'text-emerald-600 hover:text-emerald-800'} bg-transparent border-0 p-0 cursor-pointer" %>
            <%= button_to "Demote",
                  demote_admin_admin_path(id),
                  method: :patch,
                  class: "ml-4 text-xs font-medium text-amber-600 hover:text-amber-800 bg-transparent border-0 p-0 cursor-pointer" %>
          <% end %>
          <%= link_to "View", admin_admin_path(id), class: "ml-4 text-xs text-slate-500 hover:text-slate-800" %>
        </td>
      <% end %>
    <% end %>
  <% end %>
<% else %>
  <%= render EmptyStateComponent.new(message: "No admins yet. Promote a student to get started.") %>
<% end %>
```

- [ ] **Step 2: Create the admins show view**

Create `app/views/admin/admins/show.html.erb` with:

```erb
<%= render PageHeaderComponent.new(title: @admin.email, subtitle: "Admin — read-only view") do |c| %>
  <% c.with_actions do %>
    <%= render BadgeComponent.new(label: @admin.active? ? "Active" : "Inactive", variant: @admin.active? ? :success : :danger) %>
    <% if current_user.super_admin? %>
      <%= button_to @admin.active? ? "Deactivate" : "Activate",
            toggle_active_admin_admin_path(@admin),
            method: :patch,
            class: "rounded-md border px-3 py-2 text-sm font-medium focus:outline-none focus:ring-2 focus:ring-slate-500 #{@admin.active? ? 'border-red-300 text-red-600 hover:bg-red-50' : 'border-emerald-300 text-emerald-700 hover:bg-emerald-50'}" %>
      <%= button_to "Demote to User",
            demote_admin_admin_path(@admin),
            method: :patch,
            class: "rounded-md border border-amber-300 px-3 py-2 text-sm font-medium text-amber-600 hover:bg-amber-50 focus:outline-none focus:ring-2 focus:ring-amber-500" %>
    <% end %>
    <%= link_to "← All admins", admin_admins_path, class: "text-sm text-slate-500 hover:text-slate-800" %>
  <% end %>
<% end %>

<%# ── Summary stats ── %>
<% open_count   = @position_counts.fetch(true, 0) %>
<% closed_count = @position_counts.fetch(false, 0) %>
<%= render SummaryStatRowComponent.new(mb: 8) do %>
  <%= render StatCardComponent.new(label: "Realized P&L", value: format_money(@realized_pl), signed: true, color_value: @realized_pl) %>
  <%= render StatCardComponent.new(label: "Open positions", value: open_count) %>
  <%= render StatCardComponent.new(label: "Closed positions", value: closed_count) %>
<% end %>

<%# ── Recent closed positions ── %>
<%= render CardComponent.new(heading: "Recent closed positions", class: "mb-6") do %>
  <% if @recent_positions.any? %>
    <%= render DataTableComponent.new(columns: [
      { label: "Symbol",     classes: "text-left" },
      { label: "Side",       classes: "text-left" },
      { label: "Exchange",   classes: "text-left" },
      { label: "Closed at",  classes: "text-left" },
      { label: "Net P&L",    classes: "text-right" },
      { label: "ROI",        classes: "text-right" }
    ]) do |table| %>
      <% @recent_positions.each do |pos| %>
        <% table.with_row do %>
          <td class="whitespace-nowrap px-6 py-4 text-sm font-medium text-slate-900"><%= pos.symbol %></td>
          <td class="whitespace-nowrap px-6 py-4 text-sm capitalize text-slate-700"><%= pos.position_side %></td>
          <td class="whitespace-nowrap px-6 py-4 text-sm text-slate-500"><%= pos.exchange_account.provider_type.to_s.capitalize %></td>
          <td class="whitespace-nowrap px-6 py-4 text-sm text-slate-500"><%= pos.close_at&.strftime("%b %d, %Y") || "—" %></td>
          <td class="whitespace-nowrap px-6 py-4 text-right text-sm font-medium <%= pos.net_pl.to_d >= 0 ? 'text-emerald-600' : 'text-red-600' %>">
            <%= format_money(pos.net_pl) %>
          </td>
          <td class="whitespace-nowrap px-6 py-4 text-right text-sm <%= pos.roi_percent.to_d >= 0 ? 'text-emerald-600' : 'text-red-600' %>">
            <%= number_to_percentage(pos.roi_percent, precision: 2) %>
          </td>
        <% end %>
      <% end %>
    <% end %>
  <% else %>
    <p class="text-sm text-slate-500">No closed positions yet.</p>
  <% end %>
<% end %>

<%# ── Stock portfolios ── %>
<% if @stock_portfolios.any? %>
  <%= render CardComponent.new(heading: "Stock portfolios", class: "mb-6") do %>
    <div class="space-y-2">
      <% @stock_portfolios.each do |portfolio| %>
        <div class="flex items-center justify-between rounded-md border border-slate-100 px-4 py-3">
          <div>
            <span class="text-sm font-medium text-slate-900"><%= portfolio.name %></span>
            <span class="ml-2 rounded bg-slate-100 px-2 py-0.5 text-xs text-slate-500"><%= portfolio.market %></span>
          </div>
          <span class="text-sm text-slate-500"><%= portfolio.stock_trades.size %> trades</span>
        </div>
      <% end %>
    </div>
  <% end %>
<% end %>

<%# ── Spot accounts ── %>
<% if @spot_accounts.any? %>
  <%= render CardComponent.new(heading: "Spot accounts") do %>
    <div class="space-y-2">
      <% @spot_accounts.each do |account| %>
        <div class="flex items-center justify-between rounded-md border border-slate-100 px-4 py-3">
          <span class="text-sm font-medium text-slate-900"><%= account.name %></span>
          <span class="text-sm text-slate-500"><%= account.spot_transactions.size %> transactions</span>
        </div>
      <% end %>
    </div>
  <% end %>
<% end %>
```

- [ ] **Step 3: Commit**

```bash
git add app/views/admin/admins/
git commit -m "feat: add admins index and show views"
```

---

## Task 11: Update Admin Layout

**Files:**
- Modify: `app/views/layouts/admin.html.erb`

- [ ] **Step 1: Add Admins to sidebar and mobile header**

In `app/views/layouts/admin.html.erb`, replace the nav links array (lines 28–36) with:

```erb
<% [
  ["Dashboard",   admin_root_path,         "/admin"],
  ["Students",    admin_students_path,      "/admin/students"],
  ["Admins",      admin_admins_path,        "/admin/admins"],
  ["Invite Code", admin_invite_code_path,   "/admin/invite_code"],
].each do |label, path, match| %>
  <% active = match == "/admin" ? current_page?(admin_root_path) : request.path.start_with?(match) %>
  <%= link_to label, path,
        class: "flex items-center rounded-md px-3 py-2 text-sm transition-colors duration-150 #{active ? 'bg-slate-700 font-medium text-white' : 'text-slate-400 hover:bg-slate-800 hover:text-slate-100'}" %>
<% end %>
```

And replace the mobile header links (lines 51–53) with:

```erb
<%= link_to "Dashboard", admin_root_path, class: "text-slate-600 hover:text-slate-900" %>
<%= link_to "Students", admin_students_path, class: "text-slate-600 hover:text-slate-900" %>
<%= link_to "Admins", admin_admins_path, class: "text-slate-600 hover:text-slate-900" %>
<%= link_to "Invite", admin_invite_code_path, class: "text-slate-600 hover:text-slate-900" %>
```

- [ ] **Step 2: Commit**

```bash
git add app/views/layouts/admin.html.erb
git commit -m "feat: add Admins link to admin sidebar and mobile nav"
```

---

## Task 12: Update Dashboard Controller

**Files:**
- Modify: `app/controllers/admin/dashboard_controller.rb`

- [ ] **Step 1: Update the where clause**

Replace the entire contents of `app/controllers/admin/dashboard_controller.rb` with:

```ruby
# frozen_string_literal: true

class Admin::DashboardController < Admin::BaseController
  def show
    students          = User.where(role: "user")
    @total_students   = students.count
    @active_students  = students.where(active: true).count
    @pl_by_user       = Admin::StudentStats.realized_pl_by_user
    @profitable_count = @pl_by_user.count { |_, pl| pl > 0 }
    @profitable_pct   = @total_students > 0 ? (@profitable_count.to_f / @total_students * 100).round(1) : 0
    @total_realized   = @pl_by_user.values.sum
    @avg_realized     = @total_students > 0 ? @total_realized / @total_students : 0
    @leaderboard      = Admin::StudentStats.leaderboard(@pl_by_user)
  end
end
```

- [ ] **Step 2: Run the full test suite**

```bash
bin/rails test
```

Expected: all green.

- [ ] **Step 3: Commit**

```bash
git add app/controllers/admin/dashboard_controller.rb
git commit -m "fix: update DashboardController to filter students by role instead of admin boolean"
```
