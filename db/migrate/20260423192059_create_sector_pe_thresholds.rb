class CreateSectorPeThresholds < ActiveRecord::Migration[8.1]
  def change
    create_table :sector_pe_thresholds do |t|
      t.string :sector, null: false
      t.decimal :gift_max, precision: 8, scale: 2, null: false
      t.decimal :attractive_max, precision: 8, scale: 2, null: false
      t.decimal :fair_max, precision: 8, scale: 2, null: false

      t.timestamps
    end

    add_index :sector_pe_thresholds, :sector, unique: true
  end
end
