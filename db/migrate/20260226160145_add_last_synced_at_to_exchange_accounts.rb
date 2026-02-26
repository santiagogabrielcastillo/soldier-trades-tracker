class AddLastSyncedAtToExchangeAccounts < ActiveRecord::Migration[7.2]
  def change
    add_column :exchange_accounts, :last_synced_at, :datetime
  end
end
