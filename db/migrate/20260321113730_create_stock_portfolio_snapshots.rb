# frozen_string_literal: true

class CreateStockPortfolioSnapshots < ActiveRecord::Migration[7.2]
  def change
    create_table :stock_portfolio_snapshots do |t|
      t.references :stock_portfolio, null: false, foreign_key: true
      t.decimal :total_value, precision: 16, scale: 2, null: false
      t.decimal :cash_flow,   precision: 16, scale: 2, null: false, default: "0"
      t.datetime :recorded_at, null: false
      t.string :source, null: false, default: "manual"

      t.timestamps
    end

    add_index :stock_portfolio_snapshots, [:stock_portfolio_id, :recorded_at]
  end
end
