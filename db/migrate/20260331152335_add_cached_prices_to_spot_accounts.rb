class AddCachedPricesToSpotAccounts < ActiveRecord::Migration[7.2]
  def change
    add_column :spot_accounts, :cached_prices, :jsonb, default: {}
    add_column :spot_accounts, :prices_synced_at, :datetime
  end
end
