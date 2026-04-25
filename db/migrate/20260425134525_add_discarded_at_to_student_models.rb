class AddDiscardedAtToStudentModels < ActiveRecord::Migration[8.1]
  TABLES = %w[
    trades spot_transactions stock_trades portfolios
    exchange_accounts spot_accounts stock_portfolios
    allocation_buckets allocation_manual_entries
  ].freeze

  def change
    TABLES.each do |table|
      add_column table, :discarded_at, :datetime
      add_index  table, :discarded_at
    end
  end
end
