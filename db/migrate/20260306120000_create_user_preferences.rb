# frozen_string_literal: true

class CreateUserPreferences < ActiveRecord::Migration[7.2]
  def change
    create_table :user_preferences do |t|
      t.references :user, null: false, foreign_key: true
      t.string :key, null: false
      t.jsonb :value, null: false

      t.timestamps
    end

    add_index :user_preferences, %i[user_id key], unique: true
  end
end
