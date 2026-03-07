# frozen_string_literal: true

class AddExchangeAccountIdToPortfolios < ActiveRecord::Migration[7.2]
  def change
    add_reference :portfolios, :exchange_account,
                  null: true,
                  foreign_key: { to_table: :exchange_accounts, on_delete: :nullify }
  end
end
