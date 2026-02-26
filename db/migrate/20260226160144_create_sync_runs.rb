class CreateSyncRuns < ActiveRecord::Migration[7.2]
  def change
    create_table :sync_runs do |t|
      t.references :exchange_account, null: false, foreign_key: true
      t.datetime :ran_at, null: false

      t.timestamps
    end
    add_index :sync_runs, %i[exchange_account_id ran_at], name: "index_sync_runs_on_account_and_ran_at"
  end
end
