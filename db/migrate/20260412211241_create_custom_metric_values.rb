class CreateCustomMetricValues < ActiveRecord::Migration[8.1]
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
