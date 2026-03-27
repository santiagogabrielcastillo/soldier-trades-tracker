class CreateAllocationBuckets < ActiveRecord::Migration[7.2]
  def change
    create_table :allocation_buckets do |t|
      t.bigint :user_id, null: false
      t.string :name, null: false
      t.string :color, null: false
      t.decimal :target_pct, precision: 5, scale: 2
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :allocation_buckets, :user_id
    add_foreign_key :allocation_buckets, :users
  end
end
