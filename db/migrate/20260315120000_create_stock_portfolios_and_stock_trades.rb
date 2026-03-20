# frozen_string_literal: true

class CreateStockPortfoliosAndStockTrades < ActiveRecord::Migration[7.2]
  def change
    create_table :stock_portfolios do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.boolean :default, default: false, null: false

      t.timestamps
    end

    add_index :stock_portfolios, [ :user_id, :default ], name: "index_stock_portfolios_on_user_id_and_default"

    create_table :stock_trades do |t|
      t.references :stock_portfolio, null: false, foreign_key: true
      t.datetime :executed_at, null: false
      t.string :ticker, null: false
      t.string :side, null: false
      t.decimal :price_usd, precision: 20, scale: 8, null: false
      t.decimal :shares, precision: 20, scale: 8, null: false
      t.decimal :total_value_usd, precision: 20, scale: 8, null: false
      t.text :notes
      t.string :row_signature, null: false

      t.timestamps
    end

    add_index :stock_trades, [ :stock_portfolio_id, :row_signature ],
              name: "index_stock_trades_on_portfolio_id_and_row_signature",
              unique: true
    add_index :stock_trades, [ :stock_portfolio_id, :executed_at ],
              name: "index_stock_trades_on_portfolio_id_and_executed_at"
  end
end
