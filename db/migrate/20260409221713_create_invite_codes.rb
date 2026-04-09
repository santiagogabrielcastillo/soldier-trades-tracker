# frozen_string_literal: true

class CreateInviteCodes < ActiveRecord::Migration[7.2]
  def change
    create_table :invite_codes do |t|
      t.string :code, null: false, limit: 64
      t.datetime :expires_at, null: false, precision: 6
      t.timestamps
    end

    add_index :invite_codes, :code, unique: true
    add_index :invite_codes, :expires_at

    # Enforce single-row business rule at DB level.
    # A functional unique index on a constant expression prevents any second row
    # from being inserted, regardless of the code value.
    add_index :invite_codes, "(true)", unique: true, name: "index_invite_codes_singleton"
  end
end
