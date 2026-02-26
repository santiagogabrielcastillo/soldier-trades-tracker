class CreatePortfolios < ActiveRecord::Migration[7.2]
  def change
    create_table :portfolios do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.date :start_date, null: false
      t.date :end_date
      t.decimal :initial_balance, precision: 20, scale: 8, default: 0, null: false
      t.text :notes
      t.boolean :default, default: false, null: false

      t.timestamps
    end
  end
end
