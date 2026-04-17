class AddEpsFieldsToStockFundamentals < ActiveRecord::Migration[8.1]
  def change
    add_column :stock_fundamentals, :eps_next_y, :decimal, precision: 12, scale: 4
    add_column :stock_fundamentals, :eps_next_y_pct, :decimal, precision: 12, scale: 4
  end
end
