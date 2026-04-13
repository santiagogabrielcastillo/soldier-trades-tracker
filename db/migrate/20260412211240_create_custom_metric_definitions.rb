class CreateCustomMetricDefinitions < ActiveRecord::Migration[8.1]
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
