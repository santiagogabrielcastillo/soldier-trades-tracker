class AddHistoricSyncRequestedAtToExchangeAccounts < ActiveRecord::Migration[7.2]
  def change
    add_column :exchange_accounts, :historic_sync_requested_at, :datetime
  end
end
