class CreateStockAnalyses < ActiveRecord::Migration[7.2]
  def change
    create_table :stock_analyses do |t|
      t.references :user, null: false, foreign_key: true
      t.string   :ticker,             null: false
      t.string   :rating,             null: false
      t.text     :executive_summary
      t.string   :risk_reward_rating
      t.text     :thesis_breakdown
      t.text     :red_flags
      t.datetime :analyzed_at,        null: false

      t.timestamps
    end

    add_index :stock_analyses, [:user_id, :ticker], unique: true
  end
end
