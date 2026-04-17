class CreateUserApiKeys < ActiveRecord::Migration[8.1]
  def change
    create_table :user_api_keys do |t|
      t.references :user, null: false, foreign_key: true
      t.string :provider, null: false
      t.text :key
      t.text :secret
      t.timestamps
    end

    add_index :user_api_keys, [:user_id, :provider], unique: true
  end
end
