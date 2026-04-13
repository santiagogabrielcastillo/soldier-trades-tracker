# Earnings Reports & Company Profiles Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Company Profiles feature where each user can track earnings reports (quarterly + annual) per company, with reusable custom metric definitions and a time-series comparison view.

**Architecture:** `Company` (per-user, identified by ticker) owns `EarningsReport` records and `CustomMetricDefinition` records. Each `CustomMetricDefinition` defines a named, typed metric reused across reports; `CustomMetricValue` stores one value per (report, definition) pair. Dedicated controllers for companies, earnings reports, and custom metric definitions, all scoped to `current_user`.

**Tech Stack:** Rails 8, Minitest, Tailwind CSS, ViewComponents (ButtonComponent, ErrorSummaryComponent), Turbo/Stimulus, PostgreSQL

---

## File Structure

**New migrations:**
- `db/migrate/TIMESTAMP_create_companies.rb`
- `db/migrate/TIMESTAMP_create_earnings_reports.rb`
- `db/migrate/TIMESTAMP_create_custom_metric_definitions.rb`
- `db/migrate/TIMESTAMP_create_custom_metric_values.rb`

**New models:**
- `app/models/company.rb`
- `app/models/earnings_report.rb`
- `app/models/custom_metric_definition.rb`
- `app/models/custom_metric_value.rb`

**Modified models:**
- `app/models/user.rb` — add `has_many :companies`

**New controllers:**
- `app/controllers/companies_controller.rb`
- `app/controllers/earnings_reports_controller.rb`
- `app/controllers/custom_metric_definitions_controller.rb`

**New views:**
- `app/views/companies/index.html.erb`
- `app/views/companies/show.html.erb`
- `app/views/companies/_form.html.erb`
- `app/views/companies/new.html.erb`
- `app/views/companies/edit.html.erb`
- `app/views/companies/comparison.html.erb`
- `app/views/earnings_reports/show.html.erb`
- `app/views/earnings_reports/_form.html.erb`
- `app/views/earnings_reports/new.html.erb`
- `app/views/earnings_reports/edit.html.erb`

**New fixtures:**
- `test/fixtures/companies.yml`
- `test/fixtures/earnings_reports.yml`
- `test/fixtures/custom_metric_definitions.yml`
- `test/fixtures/custom_metric_values.yml`

**New tests:**
- `test/models/company_test.rb`
- `test/models/earnings_report_test.rb`
- `test/models/custom_metric_definition_test.rb`
- `test/models/custom_metric_value_test.rb`
- `test/controllers/companies_controller_test.rb`
- `test/controllers/earnings_reports_controller_test.rb`
- `test/controllers/custom_metric_definitions_controller_test.rb`

**Modified files:**
- `config/routes.rb` — add companies resource tree
- `app/views/layouts/application.html.erb` — add "Companies" nav link

---

## Task 1: Create All 4 Migrations

No TDD needed for migrations. Create all four in one shot — `CustomMetricValue` references both `EarningsReport` and `CustomMetricDefinition`, so all tables must exist together.

**Files:**
- Create: `db/migrate/TIMESTAMP_create_companies.rb`
- Create: `db/migrate/TIMESTAMP_create_earnings_reports.rb`
- Create: `db/migrate/TIMESTAMP_create_custom_metric_definitions.rb`
- Create: `db/migrate/TIMESTAMP_create_custom_metric_values.rb`

- [ ] **Step 1: Generate all 4 migrations**

```bash
bin/rails generate migration CreateCompanies user:references ticker:string name:string sector:string description:text
bin/rails generate migration CreateEarningsReports company:references period_type:string fiscal_year:integer fiscal_quarter:integer reported_on:date notes:text revenue:decimal net_income:decimal eps:decimal
bin/rails generate migration CreateCustomMetricDefinitions company:references name:string data_type:string position:integer
bin/rails generate migration CreateCustomMetricValues earnings_report:references custom_metric_definition:references decimal_value:decimal text_value:text
```

- [ ] **Step 2: Edit the companies migration**

Open `db/migrate/TIMESTAMP_create_companies.rb` and replace its content so it matches exactly:

```ruby
class CreateCompanies < ActiveRecord::Migration[8.0]
  def change
    create_table :companies do |t|
      # index: false — the composite [user_id, ticker] below covers user_id lookups
      # as its leftmost prefix (e.g. user.companies cascade delete, user.companies.ordered)
      t.references :user, null: false, foreign_key: true, index: false
      t.string :ticker, null: false
      t.string :name, null: false
      t.string :sector
      t.text :description

      t.timestamps
    end

    add_index :companies, %i[user_id ticker], unique: true
  end
end
```

- [ ] **Step 3: Edit the earnings_reports migration**

Open `db/migrate/TIMESTAMP_create_earnings_reports.rb` and replace its content:

```ruby
class CreateEarningsReports < ActiveRecord::Migration[8.0]
  def change
    create_table :earnings_reports do |t|
      # index: false — replaced by the composite sort index below, which also
      # covers company_id-only lookups as its leftmost prefix
      t.references :company, null: false, foreign_key: true, index: false
      t.string :period_type, null: false
      t.integer :fiscal_year, null: false
      t.integer :fiscal_quarter
      t.date :reported_on
      t.text :notes
      t.decimal :revenue, precision: 20, scale: 2
      t.decimal :net_income, precision: 20, scale: 2
      t.decimal :eps, precision: 12, scale: 4

      t.timestamps
    end

    # Composite sort index for the comparison view query:
    # @company.earnings_reports.order("fiscal_year DESC, fiscal_quarter DESC NULLS LAST")
    # Allows an index scan + ordered read instead of company_id range scan + filesort.
    # Also serves as the general company_id index for @company.earnings_reports queries.
    add_index :earnings_reports,
              %i[company_id fiscal_year fiscal_quarter],
              name: "idx_earnings_reports_on_company_period"

    # Two partial unique indexes to handle nullable fiscal_quarter:
    # Postgres treats NULL != NULL, so a simple unique index on all 4 columns
    # would allow duplicate annual rows. Partial indexes solve this cleanly.
    add_index :earnings_reports,
              %i[company_id fiscal_year period_type],
              unique: true,
              where: "fiscal_quarter IS NULL",
              name: "idx_earnings_reports_annual_unique"

    add_index :earnings_reports,
              %i[company_id fiscal_year fiscal_quarter period_type],
              unique: true,
              where: "fiscal_quarter IS NOT NULL",
              name: "idx_earnings_reports_quarterly_unique"
  end
end
```

- [ ] **Step 4: Edit the custom_metric_definitions migration**

Open `db/migrate/TIMESTAMP_create_custom_metric_definitions.rb` and replace:

```ruby
class CreateCustomMetricDefinitions < ActiveRecord::Migration[8.0]
  def change
    create_table :custom_metric_definitions do |t|
      # index: false — the composite [company_id, name] unique index below covers
      # company_id-only lookups as its leftmost prefix (e.g. @company.custom_metric_definitions)
      t.references :company, null: false, foreign_key: true, index: false
      t.string :name, null: false
      t.string :data_type, null: false
      t.integer :position, null: false, default: 0

      t.timestamps
    end

    add_index :custom_metric_definitions, %i[company_id name], unique: true
  end
end
```

- [ ] **Step 5: Edit the custom_metric_values migration**

Open `db/migrate/TIMESTAMP_create_custom_metric_values.rb` and replace:

```ruby
class CreateCustomMetricValues < ActiveRecord::Migration[8.0]
  def change
    create_table :custom_metric_values do |t|
      # index: false — the composite unique index below covers earnings_report_id
      # lookups as its leftmost prefix (e.g. report.custom_metric_values)
      t.references :earnings_report, null: false, foreign_key: true, index: false
      # Keep default index on custom_metric_definition_id — needed for the
      # reverse direction: defn.custom_metric_values (cascade destroy, eager loads)
      t.references :custom_metric_definition, null: false, foreign_key: true
      t.decimal :decimal_value, precision: 20, scale: 4
      t.text :text_value

      t.timestamps
    end

    add_index :custom_metric_values,
              %i[earnings_report_id custom_metric_definition_id],
              unique: true,
              name: "idx_custom_metric_values_unique"
  end
end
```

- [ ] **Step 6: Run migrations**

```bash
bin/rails db:migrate
```

Expected: 4 migrations applied with no errors.

- [ ] **Step 7: Commit**

```bash
git add db/migrate db/schema.rb
git commit -m "feat: add migrations for company profiles and earnings reports"
```

---

## Task 2: Company Model + Tests

**Files:**
- Create: `test/models/company_test.rb`
- Create: `app/models/company.rb`

- [ ] **Step 1: Write the failing test**

Create `test/models/company_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class CompanyTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
  end

  test "valid company saves" do
    company = @user.companies.build(ticker: "aapl", name: "Apple Inc.")
    assert company.valid?, company.errors.full_messages.inspect
  end

  test "ticker is upcased and stripped on validation" do
    company = @user.companies.build(ticker: "  aapl  ", name: "Apple")
    company.valid?
    assert_equal "AAPL", company.ticker
  end

  test "ticker is required" do
    company = @user.companies.build(ticker: nil, name: "Apple")
    assert_not company.valid?
    assert_includes company.errors[:ticker], "can't be blank"
  end

  test "name is required" do
    company = @user.companies.build(ticker: "AAPL", name: nil)
    assert_not company.valid?
    assert_includes company.errors[:name], "can't be blank"
  end

  test "ticker is unique per user" do
    @user.companies.create!(ticker: "AAPL", name: "Apple")
    duplicate = @user.companies.build(ticker: "aapl", name: "Apple Inc.")
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:ticker], "has already been taken"
  end

  test "same ticker is allowed for different users" do
    @user.companies.create!(ticker: "AAPL", name: "Apple")
    other = users(:two).companies.build(ticker: "AAPL", name: "Apple")
    assert other.valid?
  end

  test "destroying company cascades to earnings_reports and custom_metric_definitions" do
    company = @user.companies.create!(ticker: "TEST", name: "Test Co")
    company.earnings_reports.create!(period_type: "annual", fiscal_year: 2024)
    company.custom_metric_definitions.create!(name: "ARR", data_type: "number")
    assert_difference "EarningsReport.count", -1 do
      assert_difference "CustomMetricDefinition.count", -1 do
        company.destroy
      end
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

```bash
bin/rails test test/models/company_test.rb
```

Expected: errors like `uninitialized constant CompanyTest::Company` or `NoMethodError: undefined method 'companies'`.

- [ ] **Step 3: Create the model**

Create `app/models/company.rb`:

```ruby
# frozen_string_literal: true

class Company < ApplicationRecord
  belongs_to :user

  before_validation { self.ticker = ticker.to_s.strip.upcase }

  validates :ticker, presence: true, uniqueness: { scope: :user_id }
  validates :name, presence: true

  has_many :earnings_reports, dependent: :destroy
  has_many :custom_metric_definitions, dependent: :destroy

  scope :ordered, -> { order(:ticker) }
end
```

- [ ] **Step 4: Run test to verify it passes**

```bash
bin/rails test test/models/company_test.rb
```

Expected: 7 tests pass.

- [ ] **Step 5: Commit**

```bash
git add app/models/company.rb test/models/company_test.rb
git commit -m "feat: add Company model with per-user ticker uniqueness"
```

---

## Task 3: EarningsReport Model + Tests

**Files:**
- Create: `test/models/earnings_report_test.rb`
- Create: `app/models/earnings_report.rb`

- [ ] **Step 1: Write the failing test**

Create `test/models/earnings_report_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class EarningsReportTest < ActiveSupport::TestCase
  setup do
    @company = users(:one).companies.create!(ticker: "TEST", name: "Test Co")
  end

  test "valid quarterly report" do
    report = @company.earnings_reports.build(period_type: "quarterly", fiscal_year: 2024, fiscal_quarter: 4)
    assert report.valid?, report.errors.full_messages.inspect
  end

  test "valid annual report" do
    report = @company.earnings_reports.build(period_type: "annual", fiscal_year: 2024)
    assert report.valid?, report.errors.full_messages.inspect
  end

  test "quarterly report requires fiscal_quarter in 1..4" do
    report = @company.earnings_reports.build(period_type: "quarterly", fiscal_year: 2024, fiscal_quarter: nil)
    assert_not report.valid?
    assert_includes report.errors[:fiscal_quarter], "is required for quarterly reports"

    report.fiscal_quarter = 5
    assert_not report.valid?
    assert_includes report.errors[:fiscal_quarter], "must be between 1 and 4"
  end

  test "annual report must have nil fiscal_quarter" do
    report = @company.earnings_reports.build(period_type: "annual", fiscal_year: 2024, fiscal_quarter: 1)
    assert_not report.valid?
    assert_includes report.errors[:fiscal_quarter], "must be blank for annual reports"
  end

  test "period_type must be quarterly or annual" do
    report = @company.earnings_reports.build(period_type: "monthly", fiscal_year: 2024)
    assert_not report.valid?
    assert_includes report.errors[:period_type], "is not included in the list"
  end

  test "fiscal_year is required" do
    report = @company.earnings_reports.build(period_type: "annual", fiscal_year: nil)
    assert_not report.valid?
    assert_includes report.errors[:fiscal_year], "can't be blank"
  end

  test "period_label for quarterly" do
    report = @company.earnings_reports.build(period_type: "quarterly", fiscal_year: 2024, fiscal_quarter: 3)
    assert_equal "Q3 2024", report.period_label
  end

  test "period_label for annual" do
    report = @company.earnings_reports.build(period_type: "annual", fiscal_year: 2024)
    assert_equal "FY2024", report.period_label
  end

  test "destroying report cascades to custom_metric_values" do
    defn = @company.custom_metric_definitions.create!(name: "ARR", data_type: "number")
    report = @company.earnings_reports.create!(period_type: "annual", fiscal_year: 2023)
    report.custom_metric_values.create!(custom_metric_definition: defn, decimal_value: 100)
    assert_difference "CustomMetricValue.count", -1 do
      report.destroy
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

```bash
bin/rails test test/models/earnings_report_test.rb
```

Expected: `uninitialized constant EarningsReportTest::EarningsReport` or similar.

- [ ] **Step 3: Create the model**

Create `app/models/earnings_report.rb`:

```ruby
# frozen_string_literal: true

class EarningsReport < ApplicationRecord
  PERIOD_TYPES = %w[quarterly annual].freeze

  belongs_to :company

  has_many :custom_metric_values, dependent: :destroy

  accepts_nested_attributes_for :custom_metric_values,
    reject_if: ->(attrs) { attrs[:decimal_value].blank? && attrs[:text_value].blank? }

  validates :period_type, inclusion: { in: PERIOD_TYPES }
  validates :fiscal_year, presence: true
  validate :fiscal_quarter_matches_period_type

  def period_label
    period_type == "annual" ? "FY#{fiscal_year}" : "Q#{fiscal_quarter} #{fiscal_year}"
  end

  private

  def fiscal_quarter_matches_period_type
    if period_type == "quarterly"
      if fiscal_quarter.nil?
        errors.add(:fiscal_quarter, "is required for quarterly reports")
      elsif !(1..4).cover?(fiscal_quarter)
        errors.add(:fiscal_quarter, "must be between 1 and 4")
      end
    elsif period_type == "annual"
      errors.add(:fiscal_quarter, "must be blank for annual reports") if fiscal_quarter.present?
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

```bash
bin/rails test test/models/earnings_report_test.rb
```

Expected: 9 tests pass.

- [ ] **Step 5: Commit**

```bash
git add app/models/earnings_report.rb test/models/earnings_report_test.rb
git commit -m "feat: add EarningsReport model with period type validations"
```

---

## Task 4: CustomMetricDefinition Model + Tests

**Files:**
- Create: `test/models/custom_metric_definition_test.rb`
- Create: `app/models/custom_metric_definition.rb`

- [ ] **Step 1: Write the failing test**

Create `test/models/custom_metric_definition_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class CustomMetricDefinitionTest < ActiveSupport::TestCase
  setup do
    @company = users(:one).companies.create!(ticker: "TEST", name: "Test Co")
  end

  test "valid definition saves" do
    defn = @company.custom_metric_definitions.build(name: "ARR", data_type: "number")
    assert defn.valid?, defn.errors.full_messages.inspect
  end

  test "name is required" do
    defn = @company.custom_metric_definitions.build(name: nil, data_type: "number")
    assert_not defn.valid?
    assert_includes defn.errors[:name], "can't be blank"
  end

  test "data_type must be number, percentage, or text" do
    defn = @company.custom_metric_definitions.build(name: "X", data_type: "invalid")
    assert_not defn.valid?
    assert_includes defn.errors[:data_type], "is not included in the list"
  end

  test "data_type is required" do
    defn = @company.custom_metric_definitions.build(name: "X", data_type: nil)
    assert_not defn.valid?
    assert_includes defn.errors[:data_type], "can't be blank"
  end

  test "name is unique per company" do
    @company.custom_metric_definitions.create!(name: "ARR", data_type: "number")
    duplicate = @company.custom_metric_definitions.build(name: "ARR", data_type: "text")
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:name], "has already been taken"
  end

  test "same name allowed for different companies" do
    @company.custom_metric_definitions.create!(name: "ARR", data_type: "number")
    other = users(:one).companies.create!(ticker: "NFLX", name: "Netflix")
    defn = other.custom_metric_definitions.build(name: "ARR", data_type: "number")
    assert defn.valid?
  end

  test "all three valid data types" do
    %w[number percentage text].each do |dt|
      defn = @company.custom_metric_definitions.build(name: dt, data_type: dt)
      assert defn.valid?, "Expected #{dt} to be valid"
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

```bash
bin/rails test test/models/custom_metric_definition_test.rb
```

Expected: `uninitialized constant` error.

- [ ] **Step 3: Create the model**

Create `app/models/custom_metric_definition.rb`:

```ruby
# frozen_string_literal: true

class CustomMetricDefinition < ApplicationRecord
  DATA_TYPES = %w[number percentage text].freeze

  belongs_to :company

  has_many :custom_metric_values, dependent: :destroy

  validates :name, presence: true, uniqueness: { scope: :company_id }
  validates :data_type, presence: true, inclusion: { in: DATA_TYPES }

  scope :ordered, -> { order(:position, :name) }
end
```

- [ ] **Step 4: Run test to verify it passes**

```bash
bin/rails test test/models/custom_metric_definition_test.rb
```

Expected: 7 tests pass.

- [ ] **Step 5: Commit**

```bash
git add app/models/custom_metric_definition.rb test/models/custom_metric_definition_test.rb
git commit -m "feat: add CustomMetricDefinition model"
```

---

## Task 5: CustomMetricValue Model + Tests

**Files:**
- Create: `test/models/custom_metric_value_test.rb`
- Create: `app/models/custom_metric_value.rb`

- [ ] **Step 1: Write the failing test**

Create `test/models/custom_metric_value_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class CustomMetricValueTest < ActiveSupport::TestCase
  setup do
    @company = users(:one).companies.create!(ticker: "TEST", name: "Test Co")
    @report  = @company.earnings_reports.create!(period_type: "annual", fiscal_year: 2024)
    @number_defn     = @company.custom_metric_definitions.create!(name: "ARR", data_type: "number")
    @percentage_defn = @company.custom_metric_definitions.create!(name: "Margin", data_type: "percentage")
    @text_defn       = @company.custom_metric_definitions.create!(name: "Guidance", data_type: "text")
  end

  test "number type: decimal_value is stored, text_value is nil" do
    val = @report.custom_metric_values.build(
      custom_metric_definition: @number_defn,
      decimal_value: 42.5
    )
    assert val.valid?, val.errors.full_messages.inspect
  end

  test "percentage type: decimal_value is stored, text_value is nil" do
    val = @report.custom_metric_values.build(
      custom_metric_definition: @percentage_defn,
      decimal_value: 38.5
    )
    assert val.valid?, val.errors.full_messages.inspect
  end

  test "text type: text_value is stored, decimal_value is nil" do
    val = @report.custom_metric_values.build(
      custom_metric_definition: @text_defn,
      text_value: "Strong demand"
    )
    assert val.valid?, val.errors.full_messages.inspect
  end

  test "number type: text_value must be blank" do
    val = @report.custom_metric_values.build(
      custom_metric_definition: @number_defn,
      decimal_value: 10,
      text_value: "oops"
    )
    assert_not val.valid?
    assert_includes val.errors[:text_value], "must be blank for number metrics"
  end

  test "text type: decimal_value must be blank" do
    val = @report.custom_metric_values.build(
      custom_metric_definition: @text_defn,
      text_value: "hello",
      decimal_value: 99
    )
    assert_not val.valid?
    assert_includes val.errors[:decimal_value], "must be blank for text metrics"
  end

  test "unique per earnings_report and custom_metric_definition" do
    @report.custom_metric_values.create!(custom_metric_definition: @number_defn, decimal_value: 10)
    duplicate = @report.custom_metric_values.build(custom_metric_definition: @number_defn, decimal_value: 20)
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:custom_metric_definition_id], "has already been taken"
  end

  test "formatted_value for number" do
    val = @report.custom_metric_values.build(custom_metric_definition: @number_defn, decimal_value: 1_234_567_890)
    assert_equal "1234567890.0", val.formatted_value
  end

  test "formatted_value for percentage" do
    val = @report.custom_metric_values.build(custom_metric_definition: @percentage_defn, decimal_value: 38.57)
    assert_equal "38.57%", val.formatted_value
  end

  test "formatted_value for text" do
    val = @report.custom_metric_values.build(custom_metric_definition: @text_defn, text_value: "Good quarter")
    assert_equal "Good quarter", val.formatted_value
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

```bash
bin/rails test test/models/custom_metric_value_test.rb
```

Expected: `uninitialized constant` error.

- [ ] **Step 3: Create the model**

Create `app/models/custom_metric_value.rb`:

```ruby
# frozen_string_literal: true

class CustomMetricValue < ApplicationRecord
  belongs_to :earnings_report
  belongs_to :custom_metric_definition

  validates :custom_metric_definition_id, uniqueness: { scope: :earnings_report_id }
  validate :value_matches_data_type

  def formatted_value
    case custom_metric_definition.data_type
    when "percentage"
      "#{decimal_value}%"
    when "text"
      text_value.to_s
    else
      decimal_value.to_s
    end
  end

  private

  def value_matches_data_type
    return unless custom_metric_definition

    case custom_metric_definition.data_type
    when "number", "percentage"
      errors.add(:text_value, "must be blank for number metrics") if text_value.present?
    when "text"
      errors.add(:decimal_value, "must be blank for text metrics") if decimal_value.present?
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

```bash
bin/rails test test/models/custom_metric_value_test.rb
```

Expected: 9 tests pass.

- [ ] **Step 5: Commit**

```bash
git add app/models/custom_metric_value.rb test/models/custom_metric_value_test.rb
git commit -m "feat: add CustomMetricValue model with type-aware validation"
```

---

## Task 6: User Association + Fixtures

**Files:**
- Modify: `app/models/user.rb`
- Create: `test/fixtures/companies.yml`
- Create: `test/fixtures/earnings_reports.yml`
- Create: `test/fixtures/custom_metric_definitions.yml`
- Create: `test/fixtures/custom_metric_values.yml`

- [ ] **Step 1: Add has_many to User**

In `app/models/user.rb`, add after the existing `has_many` lines (before `def default_portfolio`):

```ruby
  has_many :companies, dependent: :destroy
```

- [ ] **Step 2: Run existing user tests to confirm no regression**

```bash
bin/rails test test/models/user_test.rb
```

Expected: all pass.

- [ ] **Step 3: Create companies fixture**

Create `test/fixtures/companies.yml`:

```yaml
apple:
  user: one
  ticker: AAPL
  name: Apple Inc.
  sector: Technology

netflix:
  user: one
  ticker: NFLX
  name: Netflix Inc.
  sector: Technology

other_user_company:
  user: two
  ticker: MSFT
  name: Microsoft Corp.
  sector: Technology
```

- [ ] **Step 4: Create custom_metric_definitions fixture**

Create `test/fixtures/custom_metric_definitions.yml`:

```yaml
apple_services:
  company: apple
  name: Services Revenue
  data_type: number
  position: 0

apple_margin:
  company: apple
  name: Gross Margin %
  data_type: percentage
  position: 1
```

- [ ] **Step 5: Create earnings_reports fixture**

Create `test/fixtures/earnings_reports.yml`:

```yaml
apple_q4_2024:
  company: apple
  period_type: quarterly
  fiscal_year: 2024
  fiscal_quarter: 4
  revenue: 124300000000.00
  net_income: 33900000000.00
  eps: 2.18

apple_q3_2024:
  company: apple
  period_type: quarterly
  fiscal_year: 2024
  fiscal_quarter: 3
  revenue: 94930000000.00
  net_income: 23200000000.00
  eps: 1.46

apple_fy2024:
  company: apple
  period_type: annual
  fiscal_year: 2024
  revenue: 391035000000.00
  net_income: 93736000000.00
  eps: 6.11
```

- [ ] **Step 6: Create custom_metric_values fixture**

Create `test/fixtures/custom_metric_values.yml`:

```yaml
apple_q4_services_val:
  earnings_report: apple_q4_2024
  custom_metric_definition: apple_services
  decimal_value: 26300000000.0

apple_q3_services_val:
  earnings_report: apple_q3_2024
  custom_metric_definition: apple_services
  decimal_value: 24213000000.0
```

- [ ] **Step 7: Run all model tests to verify fixtures load**

```bash
bin/rails test test/models/
```

Expected: all pass.

- [ ] **Step 8: Commit**

```bash
git add app/models/user.rb test/fixtures/
git commit -m "feat: add User#companies association and earnings report fixtures"
```

---

## Task 7: Routes

**Files:**
- Modify: `config/routes.rb`

- [ ] **Step 1: Add the companies resource tree**

In `config/routes.rb`, add before the closing `end` of the `draw` block (after the `admin` namespace):

```ruby
  resources :companies, only: %i[index new create show edit update destroy] do
    member do
      get :comparison
    end
    resources :earnings_reports, only: %i[new create show edit update destroy]
    resources :custom_metric_definitions, only: %i[create destroy]
  end
```

- [ ] **Step 2: Verify routes were generated**

```bash
bin/rails routes | grep companies
```

Expected output includes lines like:
```
          companies GET    /companies(.:format)                                    companies#index
                    POST   /companies(.:format)                                    companies#create
        new_company GET    /companies/new(.:format)                                companies#new
       edit_company GET    /companies/:id/edit(.:format)                           companies#edit
            company GET    /companies/:id(.:format)                                companies#show
                    PATCH  /companies/:id(.:format)                                companies#update
                    DELETE /companies/:id(.:format)                                companies#destroy
 comparison_company GET    /companies/:id/comparison(.:format)                     companies#comparison
    company_earnings_reports POST   /companies/:company_id/earnings_reports(.:format)     earnings_reports#create
```

- [ ] **Step 3: Commit**

```bash
git add config/routes.rb
git commit -m "feat: add routes for companies, earnings_reports, and custom_metric_definitions"
```

---

## Task 8: CompaniesController + Views + Tests

**Files:**
- Create: `test/controllers/companies_controller_test.rb`
- Create: `app/controllers/companies_controller.rb`
- Create: `app/views/companies/index.html.erb`
- Create: `app/views/companies/show.html.erb`
- Create: `app/views/companies/_form.html.erb`
- Create: `app/views/companies/new.html.erb`
- Create: `app/views/companies/edit.html.erb`

- [ ] **Step 1: Write the failing controller tests**

Create `test/controllers/companies_controller_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class CompaniesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @user.update!(password: "password", password_confirmation: "password")
    @company = companies(:apple)
  end

  test "index redirects to login when not signed in" do
    get companies_path
    assert_redirected_to login_path
  end

  test "index returns 200 when signed in" do
    sign_in_as(@user)
    get companies_path
    assert_response :success
    assert_select "h1", text: "Companies"
  end

  test "show returns 200 for own company" do
    sign_in_as(@user)
    get company_path(@company)
    assert_response :success
    assert_select "h1", text: /Apple Inc\./
  end

  test "show raises 404 for another user's company" do
    sign_in_as(@user)
    get company_path(companies(:other_user_company))
    assert_response :not_found
  end

  test "new returns 200" do
    sign_in_as(@user)
    get new_company_path
    assert_response :success
  end

  test "create saves company and redirects to show" do
    sign_in_as(@user)
    assert_difference "Company.count", 1 do
      post companies_path, params: { company: { ticker: "tsla", name: "Tesla Inc.", sector: "Automotive" } }
    end
    company = Company.find_by(ticker: "TSLA", user: @user)
    assert_redirected_to company_path(company)
    assert_equal "TSLA", company.ticker
  end

  test "create with invalid params renders new" do
    sign_in_as(@user)
    assert_no_difference "Company.count" do
      post companies_path, params: { company: { ticker: "", name: "" } }
    end
    assert_response :unprocessable_entity
  end

  test "edit returns 200 for own company" do
    sign_in_as(@user)
    get edit_company_path(@company)
    assert_response :success
  end

  test "update saves changes and redirects to show" do
    sign_in_as(@user)
    patch company_path(@company), params: { company: { name: "Apple Inc. Updated" } }
    assert_redirected_to company_path(@company)
    assert_equal "Apple Inc. Updated", @company.reload.name
  end

  test "update with invalid params renders edit" do
    sign_in_as(@user)
    patch company_path(@company), params: { company: { name: "" } }
    assert_response :unprocessable_entity
  end

  test "destroy deletes company and redirects to index" do
    sign_in_as(@user)
    assert_difference "Company.count", -1 do
      delete company_path(@company)
    end
    assert_redirected_to companies_path
  end

  test "cannot edit another user's company" do
    sign_in_as(@user)
    get edit_company_path(companies(:other_user_company))
    assert_response :not_found
  end

  private

  def sign_in_as(user)
    post login_path, params: { email: user.email, password: "password" }
    follow_redirect!
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

```bash
bin/rails test test/controllers/companies_controller_test.rb
```

Expected: `ActionController::RoutingError` or uninitialized constant.

- [ ] **Step 3: Create the controller**

Create `app/controllers/companies_controller.rb`:

```ruby
# frozen_string_literal: true

class CompaniesController < ApplicationController
  before_action :set_company, only: %i[show edit update destroy comparison]

  def index
    @companies = current_user.companies.ordered
  end

  def show
  end

  def new
    @company = current_user.companies.build
  end

  def create
    @company = current_user.companies.build(company_params)
    if @company.save
      redirect_to company_path(@company), notice: "#{@company.ticker} added."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @company.update(company_params)
      redirect_to company_path(@company), notice: "#{@company.ticker} updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @company.destroy
    redirect_to companies_path, notice: "#{@company.ticker} removed."
  end

  def comparison
    @definitions = @company.custom_metric_definitions.ordered
    @reports = @company.earnings_reports
      .order(Arel.sql("fiscal_year DESC, fiscal_quarter DESC NULLS LAST"))
    @values_by_report = @reports.each_with_object({}) do |report, h|
      h[report.id] = report.custom_metric_values
        .includes(:custom_metric_definition)
        .index_by(&:custom_metric_definition_id)
    end
  end

  private

  def set_company
    @company = current_user.companies.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render plain: "Not found", status: :not_found
  end

  def company_params
    params.require(:company).permit(:ticker, :name, :sector, :description)
  end
end
```

- [ ] **Step 4: Create the views**

Create `app/views/companies/index.html.erb`:

```erb
<div>
  <div class="mb-6 flex items-center justify-between">
    <h1 class="text-2xl font-semibold text-slate-900">Companies</h1>
    <%= render ButtonComponent.new(label: "New company", href: new_company_path) %>
  </div>

  <section class="rounded-lg border border-slate-200 bg-white shadow-sm">
    <% if @companies.any? %>
      <ul class="divide-y divide-slate-200">
        <% @companies.each do |company| %>
          <li class="flex items-center justify-between px-6 py-4">
            <div>
              <%= link_to company_path(company), class: "font-medium text-slate-900 hover:text-indigo-600" do %>
                <%= company.ticker %>
              <% end %>
              <span class="ml-2 text-sm text-slate-500"><%= company.name %></span>
              <% if company.sector.present? %>
                <span class="ml-2 text-xs text-slate-400">· <%= company.sector %></span>
              <% end %>
            </div>
            <div class="flex items-center gap-3">
              <%= link_to "Compare", comparison_company_path(company), class: "text-sm text-indigo-600 hover:text-indigo-800" %>
              <%= link_to "Edit", edit_company_path(company), class: "text-sm text-slate-600 hover:text-slate-900" %>
              <%= button_to "Remove", company_path(company), method: :delete,
                    data: { turbo_confirm: "Remove #{company.ticker} and all its earnings reports?" },
                    class: "text-sm text-slate-600 hover:text-red-600" %>
            </div>
          </li>
        <% end %>
      </ul>
    <% else %>
      <div class="px-6 py-12 text-center text-slate-600">
        <p class="mb-4">No companies yet. Add one to start tracking earnings reports.</p>
        <%= render ButtonComponent.new(label: "Add company", href: new_company_path, class: "inline-block") %>
      </div>
    <% end %>
  </section>
</div>
```

Create `app/views/companies/_form.html.erb`:

```erb
<%= form_with model: @company, local: true, class: "space-y-4" do |f| %>
  <%= render ErrorSummaryComponent.new(model: @company) %>

  <div class="grid grid-cols-2 gap-4">
    <div>
      <%= f.label :ticker, "Ticker", class: "block text-sm font-medium text-slate-700" %>
      <%= f.text_field :ticker, class: "mt-1 block w-full rounded-md border border-slate-300 px-3 py-2 shadow-sm focus:border-slate-500 focus:outline-none focus:ring-1 focus:ring-slate-500 uppercase", placeholder: "AAPL" %>
    </div>
    <div>
      <%= f.label :sector, "Sector (optional)", class: "block text-sm font-medium text-slate-700" %>
      <%= f.text_field :sector, class: "mt-1 block w-full rounded-md border border-slate-300 px-3 py-2 shadow-sm focus:border-slate-500 focus:outline-none focus:ring-1 focus:ring-slate-500", placeholder: "Technology" %>
    </div>
  </div>

  <div>
    <%= f.label :name, "Company name", class: "block text-sm font-medium text-slate-700" %>
    <%= f.text_field :name, class: "mt-1 block w-full rounded-md border border-slate-300 px-3 py-2 shadow-sm focus:border-slate-500 focus:outline-none focus:ring-1 focus:ring-slate-500", placeholder: "Apple Inc." %>
  </div>

  <div>
    <%= f.label :description, "Investment thesis / notes (optional)", class: "block text-sm font-medium text-slate-700" %>
    <%= f.text_area :description, rows: 3, class: "mt-1 block w-full rounded-md border border-slate-300 px-3 py-2 shadow-sm focus:border-slate-500 focus:outline-none focus:ring-1 focus:ring-slate-500", placeholder: "Why I hold or am researching this company…" %>
  </div>

  <div class="flex gap-3 pt-2">
    <%= f.submit class: "rounded-md bg-slate-800 px-4 py-2 text-sm font-medium text-white hover:bg-slate-700 focus:outline-none focus:ring-2 focus:ring-slate-500 focus:ring-offset-2" %>
    <%= link_to "Cancel", @company.new_record? ? companies_path : company_path(@company),
          class: "rounded-md border border-slate-300 bg-white px-4 py-2 text-sm font-medium text-slate-700 hover:bg-slate-50" %>
  </div>
<% end %>
```

Create `app/views/companies/new.html.erb`:

```erb
<div class="max-w-xl">
  <div class="mb-6">
    <h1 class="text-2xl font-semibold text-slate-900">Add Company</h1>
  </div>
  <%= render "form" %>
</div>
```

Create `app/views/companies/edit.html.erb`:

```erb
<div class="max-w-xl">
  <div class="mb-6">
    <h1 class="text-2xl font-semibold text-slate-900">Edit <%= @company.ticker %></h1>
  </div>
  <%= render "form" %>
</div>
```

Create `app/views/companies/show.html.erb`:

```erb
<div>
  <div class="mb-6 flex items-center justify-between">
    <div>
      <h1 class="text-2xl font-semibold text-slate-900"><%= @company.name %> (<%= @company.ticker %>)</h1>
      <% if @company.sector.present? %>
        <p class="mt-1 text-sm text-slate-500"><%= @company.sector %></p>
      <% end %>
    </div>
    <div class="flex gap-3">
      <%= link_to "Compare", comparison_company_path(@company),
            class: "rounded-md border border-slate-300 bg-white px-4 py-2 text-sm font-medium text-slate-700 hover:bg-slate-50" %>
      <%= link_to "Edit", edit_company_path(@company),
            class: "rounded-md border border-slate-300 bg-white px-4 py-2 text-sm font-medium text-slate-700 hover:bg-slate-50" %>
      <%= render ButtonComponent.new(label: "New report", href: new_company_earnings_report_path(@company)) %>
    </div>
  </div>

  <% if @company.description.present? %>
    <div class="mb-6 rounded-lg border border-slate-200 bg-white px-6 py-4 shadow-sm">
      <p class="text-sm text-slate-700 whitespace-pre-wrap"><%= @company.description %></p>
    </div>
  <% end %>

  <%# Custom metric definitions management %>
  <section class="mb-6 rounded-lg border border-slate-200 bg-white shadow-sm">
    <div class="flex items-center justify-between border-b border-slate-200 px-6 py-4">
      <h2 class="text-base font-medium text-slate-900">Custom Metrics</h2>
    </div>
    <div class="px-6 py-4">
      <% if @company.custom_metric_definitions.any? %>
        <ul class="mb-4 divide-y divide-slate-100">
          <% @company.custom_metric_definitions.ordered.each do |defn| %>
            <li class="flex items-center justify-between py-2">
              <span class="text-sm text-slate-700"><%= defn.name %>
                <span class="ml-1 text-xs text-slate-400">(<%= defn.data_type %>)</span>
              </span>
              <%= button_to "Remove", company_custom_metric_definition_path(@company, defn),
                    method: :delete,
                    data: { turbo_confirm: "Remove "#{defn.name}"? This will delete its value from all reports for #{@company.ticker}." },
                    class: "text-xs text-slate-400 hover:text-red-600" %>
            </li>
          <% end %>
        </ul>
      <% else %>
        <p class="mb-4 text-sm text-slate-500">No custom metrics yet.</p>
      <% end %>

      <%# Inline add form %>
      <%= form_with url: company_custom_metric_definitions_path(@company), local: true, class: "flex gap-2 items-end" do |f| %>
        <div class="flex-1">
          <%= f.label :name, "Metric name", class: "block text-xs font-medium text-slate-700 mb-1" %>
          <%= f.text_field :name, class: "block w-full rounded-md border border-slate-300 px-3 py-1.5 text-sm shadow-sm focus:border-slate-500 focus:outline-none focus:ring-1 focus:ring-slate-500", placeholder: "e.g. Active Users" %>
        </div>
        <div>
          <%= f.label :data_type, "Type", class: "block text-xs font-medium text-slate-700 mb-1" %>
          <%= f.select :data_type,
                options_for_select([["Number", "number"], ["Percentage", "percentage"], ["Text", "text"]]),
                {},
                { class: "block rounded-md border border-slate-300 px-3 py-1.5 text-sm shadow-sm focus:border-slate-500 focus:outline-none focus:ring-1 focus:ring-slate-500" } %>
        </div>
        <%= f.submit "Add metric", class: "rounded-md bg-slate-800 px-4 py-1.5 text-sm font-medium text-white hover:bg-slate-700" %>
      <% end %>
    </div>
  </section>

  <%# Earnings reports list %>
  <section class="rounded-lg border border-slate-200 bg-white shadow-sm">
    <div class="flex items-center justify-between border-b border-slate-200 px-6 py-4">
      <h2 class="text-base font-medium text-slate-900">Earnings Reports</h2>
    </div>
    <% reports = @company.earnings_reports.order(Arel.sql("fiscal_year DESC, fiscal_quarter DESC NULLS LAST")) %>
    <% if reports.any? %>
      <ul class="divide-y divide-slate-200">
        <% reports.each do |report| %>
          <li class="flex items-center justify-between px-6 py-4">
            <div>
              <%= link_to report.period_label, company_earnings_report_path(@company, report),
                    class: "font-medium text-slate-900 hover:text-indigo-600" %>
              <% if report.reported_on.present? %>
                <span class="ml-2 text-sm text-slate-500">Reported <%= report.reported_on.strftime("%b %d, %Y") %></span>
              <% end %>
            </div>
            <div class="flex items-center gap-3">
              <%= link_to "Edit", edit_company_earnings_report_path(@company, report),
                    class: "text-sm text-slate-600 hover:text-slate-900" %>
              <%= button_to "Remove", company_earnings_report_path(@company, report),
                    method: :delete,
                    data: { turbo_confirm: "Remove #{report.period_label}?" },
                    class: "text-sm text-slate-600 hover:text-red-600" %>
            </div>
          </li>
        <% end %>
      </ul>
    <% else %>
      <div class="px-6 py-12 text-center text-slate-600">
        <p class="mb-4">No reports yet.</p>
        <%= render ButtonComponent.new(label: "Add first report", href: new_company_earnings_report_path(@company), class: "inline-block") %>
      </div>
    <% end %>
  </section>
</div>
```

Create `app/views/companies/comparison.html.erb`:

```erb
<div>
  <div class="mb-6 flex items-center justify-between">
    <div>
      <h1 class="text-2xl font-semibold text-slate-900"><%= @company.ticker %> — Comparison</h1>
      <p class="mt-1 text-sm text-slate-500"><%= @company.name %></p>
    </div>
    <%= link_to "← Back to profile", company_path(@company),
          class: "rounded-md border border-slate-300 bg-white px-4 py-2 text-sm font-medium text-slate-700 hover:bg-slate-50" %>
  </div>

  <% if @reports.none? %>
    <div class="rounded-lg border border-slate-200 bg-white px-6 py-12 text-center text-slate-600 shadow-sm">
      <p class="mb-4">No reports yet.</p>
      <%= render ButtonComponent.new(label: "Add first report", href: new_company_earnings_report_path(@company), class: "inline-block") %>
    </div>
  <% else %>
    <div class="overflow-x-auto rounded-lg border border-slate-200 bg-white shadow-sm">
      <table class="min-w-full divide-y divide-slate-200 text-sm">
        <thead class="bg-slate-50">
          <tr>
            <th class="px-6 py-3 text-left font-medium text-slate-600 whitespace-nowrap">Metric</th>
            <% @reports.each do |report| %>
              <th class="px-6 py-3 text-right font-medium text-slate-600 whitespace-nowrap">
                <%= report.period_label %>
              </th>
            <% end %>
          </tr>
        </thead>
        <tbody class="divide-y divide-slate-200">
          <%# Standard metrics %>
          <% [["Revenue", :revenue], ["Net Income", :net_income], ["EPS", :eps]].each do |label, attr| %>
            <tr class="hover:bg-slate-50">
              <td class="px-6 py-3 font-medium text-slate-700 whitespace-nowrap"><%= label %></td>
              <% @reports.each do |report| %>
                <td class="px-6 py-3 text-right text-slate-900 tabular-nums whitespace-nowrap">
                  <%= report.send(attr)&.to_s || "—" %>
                </td>
              <% end %>
            </tr>
          <% end %>

          <%# Custom metrics %>
          <% @definitions.each do |defn| %>
            <tr class="hover:bg-slate-50">
              <td class="px-6 py-3 font-medium text-slate-700 whitespace-nowrap">
                <%= defn.name %>
                <span class="ml-1 text-xs font-normal text-slate-400">(<%= defn.data_type %>)</span>
              </td>
              <% @reports.each do |report| %>
                <td class="px-6 py-3 text-right text-slate-900 tabular-nums whitespace-nowrap">
                  <% val = @values_by_report.dig(report.id, defn.id) %>
                  <%= val&.formatted_value || "—" %>
                </td>
              <% end %>
            </tr>
          <% end %>
        </tbody>
      </table>
    </div>
  <% end %>
</div>
```

- [ ] **Step 5: Run tests**

```bash
bin/rails test test/controllers/companies_controller_test.rb
```

Expected: 12 tests pass.

- [ ] **Step 6: Commit**

```bash
git add app/controllers/companies_controller.rb app/views/companies/ test/controllers/companies_controller_test.rb
git commit -m "feat: add CompaniesController with CRUD + comparison view"
```

---

## Task 9: EarningsReportsController + Views + Tests

**Files:**
- Create: `test/controllers/earnings_reports_controller_test.rb`
- Create: `app/controllers/earnings_reports_controller.rb`
- Create: `app/views/earnings_reports/_form.html.erb`
- Create: `app/views/earnings_reports/new.html.erb`
- Create: `app/views/earnings_reports/edit.html.erb`
- Create: `app/views/earnings_reports/show.html.erb`

- [ ] **Step 1: Write the failing controller tests**

Create `test/controllers/earnings_reports_controller_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class EarningsReportsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @user.update!(password: "password", password_confirmation: "password")
    @company = companies(:apple)
    @report  = earnings_reports(:apple_q4_2024)
  end

  test "new redirects to login when not signed in" do
    get new_company_earnings_report_path(@company)
    assert_redirected_to login_path
  end

  test "new returns 200 for own company" do
    sign_in_as(@user)
    get new_company_earnings_report_path(@company)
    assert_response :success
  end

  test "new raises 404 for another user's company" do
    sign_in_as(@user)
    get new_company_earnings_report_path(companies(:other_user_company))
    assert_response :not_found
  end

  test "create saves report and redirects to company show" do
    sign_in_as(@user)
    assert_difference "EarningsReport.count", 1 do
      post company_earnings_reports_path(@company), params: {
        earnings_report: {
          period_type: "annual",
          fiscal_year: 2023,
          revenue: 383285000000,
          net_income: 96995000000,
          eps: 6.13
        }
      }
    end
    report = EarningsReport.find_by(company: @company, fiscal_year: 2023, period_type: "annual")
    assert_redirected_to company_earnings_report_path(@company, report)
  end

  test "create with invalid params renders new" do
    sign_in_as(@user)
    assert_no_difference "EarningsReport.count" do
      post company_earnings_reports_path(@company), params: {
        earnings_report: { period_type: "quarterly", fiscal_year: 2024, fiscal_quarter: nil }
      }
    end
    assert_response :unprocessable_entity
  end

  test "show returns 200 for own company's report" do
    sign_in_as(@user)
    get company_earnings_report_path(@company, @report)
    assert_response :success
    assert_select "h1", text: /Q4 2024/
  end

  test "show raises 404 for another user's company" do
    sign_in_as(@user)
    other_company = companies(:other_user_company)
    other_report  = other_company.earnings_reports.create!(period_type: "annual", fiscal_year: 2024)
    get company_earnings_report_path(other_company, other_report)
    assert_response :not_found
  end

  test "edit returns 200 for own report" do
    sign_in_as(@user)
    get edit_company_earnings_report_path(@company, @report)
    assert_response :success
  end

  test "update saves changes and redirects to show" do
    sign_in_as(@user)
    patch company_earnings_report_path(@company, @report), params: {
      earnings_report: { notes: "Beat expectations" }
    }
    assert_redirected_to company_earnings_report_path(@company, @report)
    assert_equal "Beat expectations", @report.reload.notes
  end

  test "update with invalid params renders edit" do
    sign_in_as(@user)
    patch company_earnings_report_path(@company, @report), params: {
      earnings_report: { period_type: "quarterly", fiscal_quarter: nil }
    }
    assert_response :unprocessable_entity
  end

  test "destroy removes report and redirects to company" do
    sign_in_as(@user)
    assert_difference "EarningsReport.count", -1 do
      delete company_earnings_report_path(@company, @report)
    end
    assert_redirected_to company_path(@company)
  end

  private

  def sign_in_as(user)
    post login_path, params: { email: user.email, password: "password" }
    follow_redirect!
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

```bash
bin/rails test test/controllers/earnings_reports_controller_test.rb
```

Expected: routing or uninitialized constant errors.

- [ ] **Step 3: Create the controller**

Create `app/controllers/earnings_reports_controller.rb`:

```ruby
# frozen_string_literal: true

class EarningsReportsController < ApplicationController
  before_action :set_company
  before_action :set_report, only: %i[show edit update destroy]

  def new
    @report = @company.earnings_reports.build
    build_metric_value_fields
  end

  def create
    @report = @company.earnings_reports.build(report_params)
    if @report.save
      redirect_to company_earnings_report_path(@company, @report), notice: "Report added."
    else
      build_metric_value_fields
      render :new, status: :unprocessable_entity
    end
  end

  def show
  end

  def edit
    build_metric_value_fields
  end

  def update
    if @report.update(report_params)
      redirect_to company_earnings_report_path(@company, @report), notice: "Report updated."
    else
      build_metric_value_fields
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @report.destroy
    redirect_to company_path(@company), notice: "Report removed."
  end

  private

  def set_company
    @company = current_user.companies.find(params[:company_id])
  rescue ActiveRecord::RecordNotFound
    render plain: "Not found", status: :not_found
  end

  def set_report
    @report = @company.earnings_reports.find(params[:id])
  end

  def build_metric_value_fields
    existing = @report.custom_metric_values.index_by(&:custom_metric_definition_id)
    @company.custom_metric_definitions.ordered.each do |defn|
      unless existing.key?(defn.id)
        @report.custom_metric_values.build(custom_metric_definition: defn)
      end
    end
  end

  def report_params
    params.require(:earnings_report).permit(
      :period_type, :fiscal_year, :fiscal_quarter, :reported_on, :notes,
      :revenue, :net_income, :eps,
      custom_metric_values_attributes: %i[id custom_metric_definition_id decimal_value text_value]
    )
  end
end
```

- [ ] **Step 4: Create the views**

Create `app/views/earnings_reports/_form.html.erb`:

```erb
<%= form_with model: [@company, @report], local: true, class: "space-y-6" do |f| %>
  <%= render ErrorSummaryComponent.new(model: @report) %>

  <div class="grid grid-cols-3 gap-4">
    <div>
      <%= f.label :period_type, "Period type", class: "block text-sm font-medium text-slate-700" %>
      <%= f.select :period_type,
            options_for_select([["Quarterly", "quarterly"], ["Annual", "annual"]], @report.period_type),
            {},
            { class: "mt-1 block w-full rounded-md border border-slate-300 px-3 py-2 shadow-sm focus:border-slate-500 focus:outline-none focus:ring-1 focus:ring-slate-500" } %>
    </div>
    <div>
      <%= f.label :fiscal_year, "Fiscal year", class: "block text-sm font-medium text-slate-700" %>
      <%= f.number_field :fiscal_year, class: "mt-1 block w-full rounded-md border border-slate-300 px-3 py-2 shadow-sm focus:border-slate-500 focus:outline-none focus:ring-1 focus:ring-slate-500", placeholder: "2024" %>
    </div>
    <div>
      <%= f.label :fiscal_quarter, "Quarter (Q1–Q4, leave blank for annual)", class: "block text-sm font-medium text-slate-700" %>
      <%= f.number_field :fiscal_quarter, in: 1..4, class: "mt-1 block w-full rounded-md border border-slate-300 px-3 py-2 shadow-sm focus:border-slate-500 focus:outline-none focus:ring-1 focus:ring-slate-500", placeholder: "4" %>
    </div>
  </div>

  <div>
    <%= f.label :reported_on, "Reported on (optional)", class: "block text-sm font-medium text-slate-700" %>
    <%= f.date_field :reported_on, class: "mt-1 block w-full rounded-md border border-slate-300 px-3 py-2 shadow-sm focus:border-slate-500 focus:outline-none focus:ring-1 focus:ring-slate-500" %>
  </div>

  <fieldset class="rounded-lg border border-slate-200 p-4">
    <legend class="px-2 text-sm font-medium text-slate-700">Standard Metrics</legend>
    <div class="grid grid-cols-3 gap-4">
      <div>
        <%= f.label :revenue, "Revenue", class: "block text-sm font-medium text-slate-700" %>
        <%= f.number_field :revenue, step: 0.01, class: "mt-1 block w-full rounded-md border border-slate-300 px-3 py-2 shadow-sm focus:border-slate-500 focus:outline-none focus:ring-1 focus:ring-slate-500", placeholder: "124300000000" %>
      </div>
      <div>
        <%= f.label :net_income, "Net Income", class: "block text-sm font-medium text-slate-700" %>
        <%= f.number_field :net_income, step: 0.01, class: "mt-1 block w-full rounded-md border border-slate-300 px-3 py-2 shadow-sm focus:border-slate-500 focus:outline-none focus:ring-1 focus:ring-slate-500", placeholder: "33900000000" %>
      </div>
      <div>
        <%= f.label :eps, "EPS", class: "block text-sm font-medium text-slate-700" %>
        <%= f.number_field :eps, step: 0.0001, class: "mt-1 block w-full rounded-md border border-slate-300 px-3 py-2 shadow-sm focus:border-slate-500 focus:outline-none focus:ring-1 focus:ring-slate-500", placeholder: "2.18" %>
      </div>
    </div>
  </fieldset>

  <% if @report.custom_metric_values.any? %>
    <fieldset class="rounded-lg border border-slate-200 p-4">
      <legend class="px-2 text-sm font-medium text-slate-700">Custom Metrics</legend>
      <div class="space-y-4">
        <% f.fields_for :custom_metric_values do |v| %>
          <% defn = v.object.custom_metric_definition %>
          <div>
            <%= v.hidden_field :custom_metric_definition_id %>
            <% if v.object.id.present? %>
              <%= v.hidden_field :id %>
            <% end %>
            <%= v.label defn.data_type == "text" ? :text_value : :decimal_value,
                  "#{defn.name} <span class='text-xs font-normal text-slate-400'>(#{defn.data_type})</span>".html_safe,
                  class: "block text-sm font-medium text-slate-700" %>
            <% if defn.data_type == "text" %>
              <%= v.text_area :text_value, rows: 2,
                    class: "mt-1 block w-full rounded-md border border-slate-300 px-3 py-2 shadow-sm focus:border-slate-500 focus:outline-none focus:ring-1 focus:ring-slate-500" %>
            <% else %>
              <%= v.number_field :decimal_value, step: defn.data_type == "percentage" ? 0.01 : 1,
                    class: "mt-1 block w-full rounded-md border border-slate-300 px-3 py-2 shadow-sm focus:border-slate-500 focus:outline-none focus:ring-1 focus:ring-slate-500" %>
            <% end %>
          </div>
        <% end %>
      </div>
    </fieldset>
  <% end %>

  <div>
    <%= f.label :notes, "Notes (optional)", class: "block text-sm font-medium text-slate-700" %>
    <%= f.text_area :notes, rows: 3, class: "mt-1 block w-full rounded-md border border-slate-300 px-3 py-2 shadow-sm focus:border-slate-500 focus:outline-none focus:ring-1 focus:ring-slate-500" %>
  </div>

  <div class="flex gap-3 pt-2">
    <%= f.submit class: "rounded-md bg-slate-800 px-4 py-2 text-sm font-medium text-white hover:bg-slate-700 focus:outline-none focus:ring-2 focus:ring-slate-500 focus:ring-offset-2" %>
    <%= link_to "Cancel", company_path(@company),
          class: "rounded-md border border-slate-300 bg-white px-4 py-2 text-sm font-medium text-slate-700 hover:bg-slate-50" %>
  </div>
<% end %>
```

Create `app/views/earnings_reports/new.html.erb`:

```erb
<div class="max-w-2xl">
  <div class="mb-6">
    <p class="text-sm text-slate-500">
      <%= link_to @company.ticker, company_path(@company), class: "hover:text-slate-700" %> /
    </p>
    <h1 class="text-2xl font-semibold text-slate-900">Add Earnings Report</h1>
  </div>
  <%= render "form" %>
</div>
```

Create `app/views/earnings_reports/edit.html.erb`:

```erb
<div class="max-w-2xl">
  <div class="mb-6">
    <p class="text-sm text-slate-500">
      <%= link_to @company.ticker, company_path(@company), class: "hover:text-slate-700" %> /
      <%= link_to @report.period_label, company_earnings_report_path(@company, @report), class: "hover:text-slate-700" %>
    </p>
    <h1 class="text-2xl font-semibold text-slate-900">Edit <%= @report.period_label %></h1>
  </div>
  <%= render "form" %>
</div>
```

Create `app/views/earnings_reports/show.html.erb`:

```erb
<div>
  <div class="mb-6 flex items-center justify-between">
    <div>
      <p class="text-sm text-slate-500">
        <%= link_to @company.ticker, company_path(@company), class: "hover:text-slate-700" %>
      </p>
      <h1 class="text-2xl font-semibold text-slate-900"><%= @report.period_label %></h1>
      <% if @report.reported_on.present? %>
        <p class="mt-1 text-sm text-slate-500">Reported <%= @report.reported_on.strftime("%B %d, %Y") %></p>
      <% end %>
    </div>
    <div class="flex gap-3">
      <%= link_to "Edit", edit_company_earnings_report_path(@company, @report),
            class: "rounded-md border border-slate-300 bg-white px-4 py-2 text-sm font-medium text-slate-700 hover:bg-slate-50" %>
      <%= button_to "Remove", company_earnings_report_path(@company, @report),
            method: :delete,
            data: { turbo_confirm: "Remove this report?" },
            class: "rounded-md border border-red-200 bg-white px-4 py-2 text-sm font-medium text-red-600 hover:bg-red-50" %>
    </div>
  </div>

  <div class="rounded-lg border border-slate-200 bg-white shadow-sm">
    <div class="divide-y divide-slate-200">
      <% [["Revenue", @report.revenue], ["Net Income", @report.net_income], ["EPS", @report.eps]].each do |label, value| %>
        <% next if value.nil? %>
        <div class="flex items-center justify-between px-6 py-4">
          <span class="text-sm font-medium text-slate-700"><%= label %></span>
          <span class="text-sm text-slate-900 tabular-nums"><%= value %></span>
        </div>
      <% end %>

      <% @report.custom_metric_values.includes(:custom_metric_definition).each do |val| %>
        <div class="flex items-center justify-between px-6 py-4">
          <span class="text-sm font-medium text-slate-700"><%= val.custom_metric_definition.name %></span>
          <span class="text-sm text-slate-900 tabular-nums"><%= val.formatted_value %></span>
        </div>
      <% end %>
    </div>

    <% if @report.notes.present? %>
      <div class="border-t border-slate-200 px-6 py-4">
        <p class="text-sm font-medium text-slate-700 mb-1">Notes</p>
        <p class="text-sm text-slate-600 whitespace-pre-wrap"><%= @report.notes %></p>
      </div>
    <% end %>
  </div>
</div>
```

- [ ] **Step 5: Run tests**

```bash
bin/rails test test/controllers/earnings_reports_controller_test.rb
```

Expected: 11 tests pass.

- [ ] **Step 6: Commit**

```bash
git add app/controllers/earnings_reports_controller.rb app/views/earnings_reports/ test/controllers/earnings_reports_controller_test.rb
git commit -m "feat: add EarningsReportsController with CRUD and custom metric value form"
```

---

## Task 10: CustomMetricDefinitionsController + Tests

**Files:**
- Create: `test/controllers/custom_metric_definitions_controller_test.rb`
- Create: `app/controllers/custom_metric_definitions_controller.rb`

- [ ] **Step 1: Write the failing test**

Create `test/controllers/custom_metric_definitions_controller_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class CustomMetricDefinitionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @user.update!(password: "password", password_confirmation: "password")
    @company = companies(:apple)
  end

  test "create redirects to login when not signed in" do
    post company_custom_metric_definitions_path(@company), params: { name: "ARR", data_type: "number" }
    assert_redirected_to login_path
  end

  test "create adds definition and redirects to company show" do
    sign_in_as(@user)
    assert_difference "CustomMetricDefinition.count", 1 do
      post company_custom_metric_definitions_path(@company),
           params: { name: "Active Users", data_type: "number" }
    end
    assert_redirected_to company_path(@company)
    assert CustomMetricDefinition.exists?(company: @company, name: "Active Users", data_type: "number")
  end

  test "create with invalid params redirects to company show with alert" do
    sign_in_as(@user)
    assert_no_difference "CustomMetricDefinition.count" do
      post company_custom_metric_definitions_path(@company),
           params: { name: "", data_type: "number" }
    end
    assert_redirected_to company_path(@company)
    assert_match /can't be blank/i, flash[:alert].to_s
  end

  test "create raises 404 for another user's company" do
    sign_in_as(@user)
    post company_custom_metric_definitions_path(companies(:other_user_company)),
         params: { name: "ARR", data_type: "number" }
    assert_response :not_found
  end

  test "destroy removes definition and redirects to company show" do
    sign_in_as(@user)
    defn = custom_metric_definitions(:apple_services)
    assert_difference "CustomMetricDefinition.count", -1 do
      delete company_custom_metric_definition_path(@company, defn)
    end
    assert_redirected_to company_path(@company)
  end

  test "destroy cascades to custom_metric_values" do
    sign_in_as(@user)
    defn = custom_metric_definitions(:apple_services)
    value_count_before = defn.custom_metric_values.count
    assert value_count_before > 0, "Fixture should have at least one value"
    assert_difference "CustomMetricValue.count", -value_count_before do
      delete company_custom_metric_definition_path(@company, defn)
    end
  end

  private

  def sign_in_as(user)
    post login_path, params: { email: user.email, password: "password" }
    follow_redirect!
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

```bash
bin/rails test test/controllers/custom_metric_definitions_controller_test.rb
```

Expected: routing or uninitialized constant error.

- [ ] **Step 3: Create the controller**

Create `app/controllers/custom_metric_definitions_controller.rb`:

```ruby
# frozen_string_literal: true

class CustomMetricDefinitionsController < ApplicationController
  before_action :set_company

  def create
    @definition = @company.custom_metric_definitions.build(
      name: params[:name],
      data_type: params[:data_type]
    )
    if @definition.save
      redirect_to company_path(@company), notice: "#{@definition.name} metric added."
    else
      redirect_to company_path(@company), alert: @definition.errors.full_messages.to_sentence
    end
  end

  def destroy
    definition = @company.custom_metric_definitions.find(params[:id])
    definition.destroy
    redirect_to company_path(@company), notice: "#{definition.name} metric removed."
  end

  private

  def set_company
    @company = current_user.companies.find(params[:company_id])
  rescue ActiveRecord::RecordNotFound
    render plain: "Not found", status: :not_found
  end
end
```

- [ ] **Step 4: Run tests**

```bash
bin/rails test test/controllers/custom_metric_definitions_controller_test.rb
```

Expected: 6 tests pass.

- [ ] **Step 5: Run all tests to verify no regressions**

```bash
bin/rails test
```

Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add app/controllers/custom_metric_definitions_controller.rb test/controllers/custom_metric_definitions_controller_test.rb
git commit -m "feat: add CustomMetricDefinitionsController for inline metric management"
```

---

## Task 11: Comparison View Controller Test

The comparison view was implemented in Task 8. This task adds a dedicated test for it.

**Files:**
- Modify: `test/controllers/companies_controller_test.rb`

- [ ] **Step 1: Add comparison tests to the existing controller test file**

Open `test/controllers/companies_controller_test.rb` and add these tests before the `private` method:

```ruby
  test "comparison returns 200 for own company" do
    sign_in_as(@user)
    get comparison_company_path(@company)
    assert_response :success
    assert_select "h1", text: /AAPL/
  end

  test "comparison shows standard metric rows" do
    sign_in_as(@user)
    get comparison_company_path(@company)
    assert_response :success
    assert_select "td", text: "Revenue"
    assert_select "td", text: "Net Income"
    assert_select "td", text: "EPS"
  end

  test "comparison shows custom metric definition rows" do
    sign_in_as(@user)
    get comparison_company_path(@company)
    assert_response :success
    assert_select "td", text: /Services Revenue/
  end

  test "comparison shows period labels as column headers" do
    sign_in_as(@user)
    get comparison_company_path(@company)
    assert_response :success
    assert_select "th", text: "Q4 2024"
    assert_select "th", text: "FY2024"
  end

  test "comparison raises 404 for another user's company" do
    sign_in_as(@user)
    get comparison_company_path(companies(:other_user_company))
    assert_response :not_found
  end
```

- [ ] **Step 2: Run the updated tests**

```bash
bin/rails test test/controllers/companies_controller_test.rb
```

Expected: all tests (now 17) pass.

- [ ] **Step 3: Commit**

```bash
git add test/controllers/companies_controller_test.rb
git commit -m "test: add comparison view controller tests"
```

---

## Task 12: Navigation Link

**Files:**
- Modify: `app/views/layouts/application.html.erb`

- [ ] **Step 1: Add "Companies" link to both nav arrays in the layout**

In `app/views/layouts/application.html.erb`, find the two nav arrays (one for mobile drawer, one for desktop sidebar). Both contain a list of `[label, path, match]` tuples. Add "Companies" after "Stocks":

The mobile drawer array (around line 69) changes from:
```ruby
["Stocks",            stocks_path,            "/stocks"],
["Allocation",        allocation_path,        "/allocation"],
```
to:
```ruby
["Stocks",            stocks_path,            "/stocks"],
["Companies",         companies_path,         "/companies"],
["Allocation",        allocation_path,        "/allocation"],
```

The desktop sidebar array (around line 141) gets the same change:
```ruby
["Stocks",            stocks_path,            "/stocks"],
["Companies",         companies_path,         "/companies"],
["Allocation",        allocation_path,        "/allocation"],
```

- [ ] **Step 2: Run all tests to confirm nothing broke**

```bash
bin/rails test
```

Expected: all tests pass.

- [ ] **Step 3: Commit**

```bash
git add app/views/layouts/application.html.erb
git commit -m "feat: add Companies link to navigation"
```

---

## Self-Review

### Spec Coverage Check

| Spec requirement | Covered by |
|---|---|
| Company per user, identified by ticker | Task 2 (model) + Task 8 (controller scoping) |
| Ticker normalized to uppercase, stripped | Task 2 |
| Universal standard metrics: revenue, net_income, eps | Task 3 + EarningsReport migration |
| Custom metric definitions per company | Task 4 |
| Custom metric values, type-aware validation | Task 5 |
| Two-partial-index approach for nullable fiscal_quarter | Task 1 (migration) |
| period_type enum (quarterly/annual) + fiscal_quarter validation | Task 3 |
| period_label helper | Task 3 |
| accepts_nested_attributes_for on EarningsReport | Task 3 + Task 9 (form) |
| CompaniesController CRUD scoped to current_user | Task 8 |
| EarningsReportsController CRUD scoped through company | Task 9 |
| CustomMetricDefinitionsController create/destroy | Task 10 |
| Comparison view showing metrics across periods | Task 8 (view + controller action) + Task 11 (tests) |
| Comparison: standard metrics + custom metrics rows | Task 8 (comparison.html.erb) |
| Company show: inline metric definition management | Task 8 (show.html.erb) |
| Destruction cascade warnings in UI | Task 8 (show: turbo_confirm on remove metric) |
| Navigation link | Task 12 |
| No PDF upload / no Finnhub coupling | Not implemented (correct per spec) |

### Placeholder Scan

No "TBD", "TODO", or vague instructions found. All steps include exact code.

### Type Consistency Check

- `Company#earnings_reports` / `Company#custom_metric_definitions` — defined in Task 2, referenced in Tasks 3–12 ✓
- `EarningsReport#custom_metric_values` + `accepts_nested_attributes_for` — defined in Task 3, used in Task 9 controller/form ✓
- `CustomMetricDefinition#ordered` scope — defined in Task 4, used in Tasks 8, 9, 10 ✓
- `CustomMetricValue#formatted_value` — defined in Task 5, used in Tasks 8 (comparison) and 9 (show) ✓
- `EarningsReport#period_label` — defined in Task 3, used in Tasks 8, 9, 11 ✓
- `set_company` rescue pattern — consistent across all three controllers (Tasks 8, 9, 10) ✓
- `@values_by_report.dig(report.id, defn.id)` in comparison.html.erb — built in `CompaniesController#comparison` as `@values_by_report[report.id] = ... .index_by(&:custom_metric_definition_id)`, so `dig` returns a `CustomMetricValue` or nil ✓
- Fixture name `apple_services` referenced in `custom_metric_definitions_controller_test.rb` — matches `test/fixtures/custom_metric_definitions.yml` ✓
- Fixture name `apple_q4_2024` referenced in `earnings_reports_controller_test.rb` — matches `test/fixtures/earnings_reports.yml` ✓
