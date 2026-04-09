class AddExtendedFieldsToStockFundamentals < ActiveRecord::Migration[7.2]
  def change
    add_column :stock_fundamentals, :sector,    :string
    add_column :stock_fundamentals, :industry,  :string
    add_column :stock_fundamentals, :ev_ebitda, :decimal, precision: 12, scale: 4
  end
end
