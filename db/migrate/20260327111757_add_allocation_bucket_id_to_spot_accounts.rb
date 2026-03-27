class AddAllocationBucketIdToSpotAccounts < ActiveRecord::Migration[7.2]
  def change
    add_column :spot_accounts, :allocation_bucket_id, :bigint
    add_index :spot_accounts, :allocation_bucket_id
    add_foreign_key :spot_accounts, :allocation_buckets, on_delete: :nullify
  end
end
