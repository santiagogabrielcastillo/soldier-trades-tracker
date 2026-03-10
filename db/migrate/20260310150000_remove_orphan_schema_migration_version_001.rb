# frozen_string_literal: true

class RemoveOrphanSchemaMigrationVersion001 < ActiveRecord::Migration[7.2]
  def up
    # Remove orphan versions with no migration file (Rails may store as "1" or "001")
    execute <<-SQL.squish
      DELETE FROM schema_migrations WHERE version IN ('1', '001')
    SQL
  end

  def down
    # Orphan version had no file; do not re-insert to avoid NO FILE status again
  end
end
