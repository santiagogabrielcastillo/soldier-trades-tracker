class AddSyncFailureTrackingToExchangeAccounts < ActiveRecord::Migration[7.2]
  def change
    add_column :exchange_accounts, :last_sync_failed_at, :datetime
    add_column :exchange_accounts, :last_sync_error, :string
  end
end
