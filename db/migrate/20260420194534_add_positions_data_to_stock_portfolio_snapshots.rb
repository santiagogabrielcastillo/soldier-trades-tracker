class AddPositionsDataToStockPortfolioSnapshots < ActiveRecord::Migration[8.1]
  def change
    add_column :stock_portfolio_snapshots, :positions_data, :jsonb, default: [], null: false
  end
end
