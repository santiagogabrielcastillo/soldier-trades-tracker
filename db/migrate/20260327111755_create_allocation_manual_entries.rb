class CreateAllocationManualEntries < ActiveRecord::Migration[7.2]
  def change
    create_table :allocation_manual_entries do |t|
      t.bigint :user_id, null: false
      t.bigint :allocation_bucket_id, null: false
      t.string :label, null: false
      t.decimal :amount_usd, precision: 20, scale: 2, null: false
      t.timestamps
    end
    add_index :allocation_manual_entries, :user_id
    add_index :allocation_manual_entries, :allocation_bucket_id
    add_foreign_key :allocation_manual_entries, :users
    add_foreign_key :allocation_manual_entries, :allocation_buckets
  end
end
