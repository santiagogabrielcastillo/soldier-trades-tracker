# frozen_string_literal: true

class RenameExchangeAccountsEncryptedColumns < ActiveRecord::Migration[7.2]
  def change
    rename_column :exchange_accounts, :encrypted_api_key, :api_key_ciphertext
    rename_column :exchange_accounts, :encrypted_api_secret, :api_secret_ciphertext
  end
end
