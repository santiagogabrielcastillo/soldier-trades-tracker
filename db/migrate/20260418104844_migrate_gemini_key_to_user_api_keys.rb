class MigrateGeminiKeyToUserApiKeys < ActiveRecord::Migration[8.1]
  def up
    User.find_each do |user|
      next if user.gemini_api_key.blank?
      UserApiKey.find_or_create_by!(user: user, provider: "gemini") do |r|
        r.key = user.gemini_api_key
      end
    end

    remove_column :users, :gemini_api_key
  end

  def down
    add_column :users, :gemini_api_key, :text
  end
end
