class AddSalesAndDebtToStockFundamentals < ActiveRecord::Migration[7.2]
  def change
    add_column :stock_fundamentals, :debt_eq,   :decimal, precision: 12, scale: 4
    add_column :stock_fundamentals, :sales_5y,  :decimal, precision: 12, scale: 4
    add_column :stock_fundamentals, :sales_qq,  :decimal, precision: 12, scale: 4
  end
end
