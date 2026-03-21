class CreateWatchlistTickers < ActiveRecord::Migration[7.2]
  def change
    create_table :watchlist_tickers do |t|
      t.references :user, null: false, foreign_key: true
      t.string :ticker, null: false

      t.timestamps
    end
    add_index :watchlist_tickers, %i[user_id ticker], unique: true
  end
end
