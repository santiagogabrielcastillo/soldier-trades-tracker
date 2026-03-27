class AddAllocationBucketIdToStockPortfolios < ActiveRecord::Migration[7.2]
  def change
    add_column :stock_portfolios, :allocation_bucket_id, :bigint
    add_index :stock_portfolios, :allocation_bucket_id
    add_foreign_key :stock_portfolios, :allocation_buckets, on_delete: :nullify
  end
end
