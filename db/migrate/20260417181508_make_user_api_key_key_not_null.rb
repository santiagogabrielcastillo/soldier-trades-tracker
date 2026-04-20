class MakeUserApiKeyKeyNotNull < ActiveRecord::Migration[8.1]
  def up
    change_column_null :user_api_keys, :key, false, ""
  end

  def down
    change_column_null :user_api_keys, :key, true
  end
end
