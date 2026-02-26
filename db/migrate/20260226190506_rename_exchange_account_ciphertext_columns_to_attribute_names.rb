class RenameExchangeAccountCiphertextColumnsToAttributeNames < ActiveRecord::Migration[7.2]
  def change
    rename_column :exchange_accounts, :api_key_ciphertext, :api_key
    rename_column :exchange_accounts, :api_secret_ciphertext, :api_secret
  end
end
