class AddCedearRatioToStockTrades < ActiveRecord::Migration[7.2]
  def change
    add_column :stock_trades, :cedear_ratio, :decimal, precision: 10, scale: 4
  end
end
