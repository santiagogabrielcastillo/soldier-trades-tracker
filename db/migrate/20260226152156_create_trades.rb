class CreateTrades < ActiveRecord::Migration[7.2]
  def change
    create_table :trades do |t|
      t.references :exchange_account, null: false, foreign_key: true
      t.string :exchange_reference_id, null: false
      t.string :symbol, null: false
      t.string :side, null: false
      t.decimal :fee, precision: 20, scale: 8
      t.decimal :net_amount, precision: 20, scale: 8, null: false
      t.datetime :executed_at, null: false
      t.jsonb :raw_payload, default: {}

      t.timestamps
    end
    add_index :trades, %i[exchange_account_id exchange_reference_id], unique: true, name: "index_trades_on_account_and_reference"
  end
end
