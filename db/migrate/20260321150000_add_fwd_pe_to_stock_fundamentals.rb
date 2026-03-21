class AddFwdPeToStockFundamentals < ActiveRecord::Migration[7.2]
  def change
    add_column :stock_fundamentals, :fwd_pe, :decimal, precision: 12, scale: 4
  end
end
