class CreateCompanies < ActiveRecord::Migration[8.1]
  def change
    create_table :companies do |t|
      # index: false — the composite [user_id, ticker] below covers user_id lookups
      # as its leftmost prefix (e.g. user.companies cascade delete, user.companies.ordered)
      t.references :user, null: false, foreign_key: true, index: false
      t.string :ticker, null: false
      t.string :name, null: false
      t.string :sector
      t.text :description

      t.timestamps
    end

    add_index :companies, %i[user_id ticker], unique: true
  end
end
