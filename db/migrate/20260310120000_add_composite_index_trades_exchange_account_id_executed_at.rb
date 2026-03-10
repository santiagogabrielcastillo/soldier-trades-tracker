# frozen_string_literal: true

class AddCompositeIndexTradesExchangeAccountIdExecutedAt < ActiveRecord::Migration[7.2]
  def change
    add_index :trades,
              %i[exchange_account_id executed_at],
              name: "index_trades_on_exchange_account_id_and_executed_at"
  end
end
