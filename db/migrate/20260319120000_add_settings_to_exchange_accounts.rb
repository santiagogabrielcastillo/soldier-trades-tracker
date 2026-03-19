# frozen_string_literal: true

class AddSettingsToExchangeAccounts < ActiveRecord::Migration[7.2]
  def change
    add_column :exchange_accounts, :settings, :jsonb, null: false, default: {}
  end
end
