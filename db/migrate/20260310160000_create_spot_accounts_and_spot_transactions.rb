# frozen_string_literal: true

class CreateSpotAccountsAndSpotTransactions < ActiveRecord::Migration[7.2]
  def change
    create_table :spot_accounts do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.boolean :default, default: false, null: false

      t.timestamps
    end

    add_index :spot_accounts, [ :user_id, :default ], name: "index_spot_accounts_on_user_id_and_default"

    create_table :spot_transactions do |t|
      t.references :spot_account, null: false, foreign_key: true
      t.datetime :executed_at, null: false
      t.string :token, null: false
      t.string :side, null: false
      t.decimal :price_usd, precision: 20, scale: 8, null: false
      t.decimal :amount, precision: 20, scale: 8, null: false
      t.decimal :total_value_usd, precision: 20, scale: 8, null: false
      t.text :notes
      t.string :row_signature, null: false

      t.timestamps
    end

    add_index :spot_transactions, [ :spot_account_id, :row_signature ],
              name: "index_spot_transactions_on_spot_account_id_and_row_signature",
              unique: true
    add_index :spot_transactions, [ :spot_account_id, :executed_at ],
              name: "index_spot_transactions_on_spot_account_id_and_executed_at"
  end
end
