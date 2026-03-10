# frozen_string_literal: true

class CreatePositionsAndPositionTrades < ActiveRecord::Migration[7.2]
  def change
    create_table :positions do |t|
      t.references :exchange_account, null: false, foreign_key: true
      t.string :symbol, null: false
      t.string :position_side
      t.integer :leverage
      t.datetime :open_at, null: false
      t.datetime :close_at
      t.decimal :margin_used, precision: 20, scale: 8
      t.decimal :net_pl, precision: 20, scale: 8, default: 0, null: false
      t.decimal :entry_price, precision: 20, scale: 8
      t.decimal :exit_price, precision: 20, scale: 8
      t.decimal :open_quantity, precision: 20, scale: 8
      t.decimal :closed_quantity, precision: 20, scale: 8
      t.decimal :total_commission, precision: 20, scale: 8, default: 0, null: false
      t.boolean :open, null: false, default: true
      t.boolean :excess_from_over_close, null: false, default: false

      t.timestamps
    end

    add_index :positions, [ :exchange_account_id, :open, :close_at ],
              name: "index_positions_on_account_open_close_at"

    create_table :position_trades do |t|
      t.references :position, null: false, foreign_key: true
      t.references :trade, null: false, foreign_key: true

      t.timestamps
    end

    add_index :position_trades, [ :position_id, :trade_id ],
              name: "index_position_trades_on_position_id_and_trade_id",
              unique: true
  end
end
