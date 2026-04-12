class CreateEarningsReports < ActiveRecord::Migration[8.1]
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
    # Also serves as the general company_id index for @company.earnings_reports queries.
    add_index :earnings_reports,
              %i[company_id fiscal_year fiscal_quarter],
              name: "idx_earnings_reports_on_company_period"

    # Two partial unique indexes to handle nullable fiscal_quarter:
    # Postgres treats NULL != NULL, so a simple unique index would allow duplicate annual rows.
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
