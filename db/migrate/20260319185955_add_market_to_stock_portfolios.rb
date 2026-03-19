class AddMarketToStockPortfolios < ActiveRecord::Migration[7.2]
  def change
    add_column :stock_portfolios, :market, :string, null: false, default: "us"
  end
end
