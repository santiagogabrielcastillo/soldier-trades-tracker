class AddGeminiApiKeyToUsers < ActiveRecord::Migration[7.2]
  def change
    add_column :users, :gemini_api_key, :text
  end
end
