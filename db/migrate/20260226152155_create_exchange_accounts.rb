class CreateExchangeAccounts < ActiveRecord::Migration[7.2]
  def change
    create_table :exchange_accounts do |t|
      t.references :user, null: false, foreign_key: true
      t.string :provider_type
      t.string :encrypted_api_key
      t.string :encrypted_api_secret
      t.datetime :linked_at

      t.timestamps
    end
  end
end
