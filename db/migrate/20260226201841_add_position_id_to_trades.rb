class AddPositionIdToTrades < ActiveRecord::Migration[7.2]
  def up
    add_column :trades, :position_id, :string
    add_index :trades, %i[exchange_account_id position_id], name: "index_trades_on_account_and_position_id"
    execute <<-SQL.squish
      UPDATE trades SET position_id = raw_payload->>'positionID'
      WHERE raw_payload ? 'positionID' AND (raw_payload->>'positionID') IS NOT NULL AND (raw_payload->>'positionID') != ''
    SQL
  end

  def down
    remove_index :trades, name: "index_trades_on_account_and_position_id" if index_exists?(:trades, %i[exchange_account_id position_id], name: "index_trades_on_account_and_position_id")
    remove_column :trades, :position_id
  end
end
