class CreateStockFundamentals < ActiveRecord::Migration[7.2]
  def change
    create_table :stock_fundamentals do |t|
      t.string :ticker, null: false
      t.decimal :pe,         precision: 12, scale: 4
      t.decimal :peg,        precision: 12, scale: 4
      t.decimal :ps,         precision: 12, scale: 4
      t.decimal :pfcf,       precision: 12, scale: 4
      t.decimal :net_margin, precision: 12, scale: 4
      t.decimal :roe,        precision: 12, scale: 4
      t.decimal :roic,       precision: 12, scale: 4
      t.datetime :fetched_at, null: false

      t.timestamps
    end
    add_index :stock_fundamentals, :ticker, unique: true
  end
end
