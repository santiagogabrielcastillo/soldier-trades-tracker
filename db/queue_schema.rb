# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_04_17_121843) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "allocation_buckets", force: :cascade do |t|
    t.string "color", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.decimal "target_pct", precision: 5, scale: 2
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_allocation_buckets_on_user_id"
  end

  create_table "allocation_manual_entries", force: :cascade do |t|
    t.bigint "allocation_bucket_id", null: false
    t.decimal "amount_usd", precision: 20, scale: 2, null: false
    t.datetime "created_at", null: false
    t.string "label", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["allocation_bucket_id"], name: "index_allocation_manual_entries_on_allocation_bucket_id"
    t.index ["user_id"], name: "index_allocation_manual_entries_on_user_id"
  end

  create_table "cedear_instruments", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.decimal "ratio", precision: 10, scale: 4, null: false
    t.string "ticker", null: false
    t.string "underlying_ticker"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id", "ticker"], name: "index_cedear_instruments_on_user_id_and_ticker", unique: true
    t.index ["user_id"], name: "index_cedear_instruments_on_user_id"
  end

  create_table "companies", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.string "name", null: false
    t.string "sector"
    t.string "ticker", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id", "ticker"], name: "index_companies_on_user_id_and_ticker", unique: true
  end

  create_table "custom_metric_definitions", force: :cascade do |t|
    t.bigint "company_id", null: false
    t.datetime "created_at", null: false
    t.string "data_type", null: false
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["company_id", "name"], name: "index_custom_metric_definitions_on_company_id_and_name", unique: true
  end

  create_table "custom_metric_values", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "custom_metric_definition_id", null: false
    t.decimal "decimal_value", precision: 20, scale: 4
    t.bigint "earnings_report_id", null: false
    t.text "text_value"
    t.datetime "updated_at", null: false
    t.index ["custom_metric_definition_id"], name: "index_custom_metric_values_on_custom_metric_definition_id"
    t.index ["earnings_report_id", "custom_metric_definition_id"], name: "idx_custom_metric_values_unique", unique: true
  end

  create_table "earnings_reports", force: :cascade do |t|
    t.bigint "company_id", null: false
    t.datetime "created_at", null: false
    t.decimal "eps", precision: 12, scale: 4
    t.integer "fiscal_quarter"
    t.integer "fiscal_year", null: false
    t.decimal "net_income", precision: 20, scale: 2
    t.text "notes"
    t.string "period_type", null: false
    t.date "reported_on"
    t.decimal "revenue", precision: 20, scale: 2
    t.datetime "updated_at", null: false
    t.index ["company_id", "fiscal_year", "fiscal_quarter", "period_type"], name: "idx_earnings_reports_quarterly_unique", unique: true, where: "(fiscal_quarter IS NOT NULL)"
    t.index ["company_id", "fiscal_year", "fiscal_quarter"], name: "idx_earnings_reports_on_company_period"
    t.index ["company_id", "fiscal_year", "period_type"], name: "idx_earnings_reports_annual_unique", unique: true, where: "(fiscal_quarter IS NULL)"
  end

  create_table "exchange_accounts", force: :cascade do |t|
    t.string "api_key"
    t.string "api_secret"
    t.datetime "created_at", null: false
    t.datetime "historic_sync_requested_at"
    t.string "last_sync_error"
    t.datetime "last_sync_failed_at"
    t.datetime "last_synced_at"
    t.datetime "linked_at"
    t.string "provider_type"
    t.jsonb "settings", default: {}, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_exchange_accounts_on_user_id"
  end

  create_table "invite_codes", force: :cascade do |t|
    t.string "code", limit: 64, null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.datetime "updated_at", null: false
    t.index "(true)", name: "index_invite_codes_singleton", unique: true
    t.index ["code"], name: "index_invite_codes_on_code", unique: true
    t.index ["expires_at"], name: "index_invite_codes_on_expires_at"
  end

  create_table "portfolios", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "default", default: false, null: false
    t.date "end_date"
    t.bigint "exchange_account_id"
    t.decimal "initial_balance", precision: 20, scale: 8, default: "0.0", null: false
    t.string "name", null: false
    t.text "notes"
    t.date "start_date", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["exchange_account_id"], name: "index_portfolios_on_exchange_account_id"
    t.index ["user_id"], name: "index_portfolios_on_user_id"
  end

  create_table "position_trades", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "position_id", null: false
    t.bigint "trade_id", null: false
    t.datetime "updated_at", null: false
    t.index ["position_id", "trade_id"], name: "index_position_trades_on_position_id_and_trade_id", unique: true
    t.index ["position_id"], name: "index_position_trades_on_position_id"
    t.index ["trade_id"], name: "index_position_trades_on_trade_id"
  end

  create_table "positions", force: :cascade do |t|
    t.datetime "close_at"
    t.decimal "closed_quantity", precision: 20, scale: 8
    t.datetime "created_at", null: false
    t.decimal "entry_price", precision: 20, scale: 8
    t.boolean "excess_from_over_close", default: false, null: false
    t.bigint "exchange_account_id", null: false
    t.decimal "exit_price", precision: 20, scale: 8
    t.integer "leverage"
    t.decimal "margin_used", precision: 20, scale: 8
    t.decimal "net_pl", precision: 20, scale: 8, default: "0.0", null: false
    t.boolean "open", default: true, null: false
    t.datetime "open_at", null: false
    t.decimal "open_quantity", precision: 20, scale: 8
    t.string "position_side"
    t.string "symbol", null: false
    t.decimal "total_commission", precision: 20, scale: 8, default: "0.0", null: false
    t.datetime "updated_at", null: false
    t.index ["exchange_account_id", "open", "close_at"], name: "index_positions_on_account_open_close_at"
    t.index ["exchange_account_id"], name: "index_positions_on_exchange_account_id"
  end

  create_table "solid_queue_blocked_executions", force: :cascade do |t|
    t.string "concurrency_key", null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.index ["concurrency_key", "priority", "job_id"], name: "index_solid_queue_blocked_executions_for_release"
    t.index ["expires_at", "concurrency_key"], name: "index_solid_queue_blocked_executions_for_maintenance"
    t.index ["job_id"], name: "index_solid_queue_blocked_executions_on_job_id", unique: true
  end

  create_table "solid_queue_claimed_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.bigint "process_id"
    t.index ["job_id"], name: "index_solid_queue_claimed_executions_on_job_id", unique: true
    t.index ["process_id", "job_id"], name: "index_solid_queue_claimed_executions_on_process_id_and_job_id"
  end

  create_table "solid_queue_failed_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "error"
    t.bigint "job_id", null: false
    t.index ["job_id"], name: "index_solid_queue_failed_executions_on_job_id", unique: true
  end

  create_table "solid_queue_jobs", force: :cascade do |t|
    t.string "active_job_id"
    t.text "arguments"
    t.string "class_name", null: false
    t.string "concurrency_key"
    t.datetime "created_at", null: false
    t.datetime "finished_at"
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.datetime "scheduled_at"
    t.datetime "updated_at", null: false
    t.index ["active_job_id"], name: "index_solid_queue_jobs_on_active_job_id"
    t.index ["class_name"], name: "index_solid_queue_jobs_on_class_name"
    t.index ["finished_at"], name: "index_solid_queue_jobs_on_finished_at"
    t.index ["queue_name", "finished_at"], name: "index_solid_queue_jobs_for_filtering"
    t.index ["scheduled_at", "finished_at"], name: "index_solid_queue_jobs_for_alerting"
  end

  create_table "solid_queue_pauses", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "queue_name", null: false
    t.index ["queue_name"], name: "index_solid_queue_pauses_on_queue_name", unique: true
  end

  create_table "solid_queue_processes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "hostname"
    t.string "kind", null: false
    t.datetime "last_heartbeat_at", null: false
    t.text "metadata"
    t.string "name", null: false
    t.integer "pid", null: false
    t.bigint "supervisor_id"
    t.index ["last_heartbeat_at"], name: "index_solid_queue_processes_on_last_heartbeat_at"
    t.index ["name", "supervisor_id"], name: "index_solid_queue_processes_on_name_and_supervisor_id", unique: true
    t.index ["supervisor_id"], name: "index_solid_queue_processes_on_supervisor_id"
  end

  create_table "solid_queue_ready_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.index ["job_id"], name: "index_solid_queue_ready_executions_on_job_id", unique: true
    t.index ["priority", "job_id"], name: "index_solid_queue_poll_all"
    t.index ["queue_name", "priority", "job_id"], name: "index_solid_queue_poll_by_queue"
  end

  create_table "solid_queue_recurring_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.datetime "run_at", null: false
    t.string "task_key", null: false
    t.index ["job_id"], name: "index_solid_queue_recurring_executions_on_job_id", unique: true
    t.index ["task_key", "run_at"], name: "index_solid_queue_recurring_executions_on_task_key_and_run_at", unique: true
  end

  create_table "solid_queue_recurring_tasks", force: :cascade do |t|
    t.text "arguments"
    t.string "class_name"
    t.string "command", limit: 2048
    t.datetime "created_at", null: false
    t.text "description"
    t.string "key", null: false
    t.integer "priority", default: 0
    t.string "queue_name"
    t.string "schedule", null: false
    t.boolean "static", default: true, null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_solid_queue_recurring_tasks_on_key", unique: true
    t.index ["static"], name: "index_solid_queue_recurring_tasks_on_static"
  end

  create_table "solid_queue_scheduled_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.datetime "scheduled_at", null: false
    t.index ["job_id"], name: "index_solid_queue_scheduled_executions_on_job_id", unique: true
    t.index ["scheduled_at", "priority", "job_id"], name: "index_solid_queue_dispatch_all"
  end

  create_table "solid_queue_semaphores", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.integer "value", default: 1, null: false
    t.index ["expires_at"], name: "index_solid_queue_semaphores_on_expires_at"
    t.index ["key", "value"], name: "index_solid_queue_semaphores_on_key_and_value"
    t.index ["key"], name: "index_solid_queue_semaphores_on_key", unique: true
  end

  create_table "spot_accounts", force: :cascade do |t|
    t.bigint "allocation_bucket_id"
    t.jsonb "cached_prices", default: {}
    t.datetime "created_at", null: false
    t.boolean "default", default: false, null: false
    t.string "name", null: false
    t.datetime "prices_synced_at"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["allocation_bucket_id"], name: "index_spot_accounts_on_allocation_bucket_id"
    t.index ["user_id", "default"], name: "index_spot_accounts_on_user_id_and_default"
    t.index ["user_id"], name: "index_spot_accounts_on_user_id"
  end

  create_table "spot_transactions", force: :cascade do |t|
    t.decimal "amount", precision: 20, scale: 8, null: false
    t.datetime "created_at", null: false
    t.datetime "executed_at", null: false
    t.text "notes"
    t.decimal "price_usd", precision: 20, scale: 8, null: false
    t.string "row_signature", null: false
    t.string "side", null: false
    t.bigint "spot_account_id", null: false
    t.string "token", null: false
    t.decimal "total_value_usd", precision: 20, scale: 8, null: false
    t.datetime "updated_at", null: false
    t.index ["spot_account_id", "executed_at"], name: "index_spot_transactions_on_spot_account_id_and_executed_at"
    t.index ["spot_account_id", "row_signature"], name: "index_spot_transactions_on_spot_account_id_and_row_signature", unique: true
    t.index ["spot_account_id"], name: "index_spot_transactions_on_spot_account_id"
  end

  create_table "stock_analyses", force: :cascade do |t|
    t.datetime "analyzed_at", null: false
    t.datetime "created_at", null: false
    t.text "executive_summary"
    t.string "provider", default: "gemini"
    t.string "rating", null: false
    t.text "red_flags"
    t.string "risk_reward_rating"
    t.jsonb "structured_data"
    t.text "thesis_breakdown"
    t.string "ticker", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id", "ticker"], name: "index_stock_analyses_on_user_id_and_ticker", unique: true
    t.index ["user_id"], name: "index_stock_analyses_on_user_id"
  end

  create_table "stock_fundamentals", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.decimal "debt_eq", precision: 12, scale: 4
    t.decimal "eps_next_y", precision: 12, scale: 4
    t.decimal "eps_next_y_pct", precision: 12, scale: 4
    t.decimal "ev_ebitda", precision: 12, scale: 4
    t.datetime "fetched_at", null: false
    t.decimal "fwd_pe", precision: 12, scale: 4
    t.string "industry"
    t.decimal "net_margin", precision: 12, scale: 4
    t.decimal "pe", precision: 12, scale: 4
    t.decimal "peg", precision: 12, scale: 4
    t.decimal "pfcf", precision: 12, scale: 4
    t.decimal "ps", precision: 12, scale: 4
    t.decimal "roe", precision: 12, scale: 4
    t.decimal "roic", precision: 12, scale: 4
    t.decimal "sales_5y", precision: 12, scale: 4
    t.decimal "sales_qq", precision: 12, scale: 4
    t.string "sector"
    t.string "ticker", null: false
    t.datetime "updated_at", null: false
    t.index ["ticker"], name: "index_stock_fundamentals_on_ticker", unique: true
  end

  create_table "stock_portfolio_snapshots", force: :cascade do |t|
    t.decimal "cash_flow", precision: 16, scale: 2, default: "0.0", null: false
    t.datetime "created_at", null: false
    t.datetime "recorded_at", null: false
    t.string "source", default: "manual", null: false
    t.bigint "stock_portfolio_id", null: false
    t.decimal "total_value", precision: 16, scale: 2, null: false
    t.datetime "updated_at", null: false
    t.index ["stock_portfolio_id", "recorded_at"], name: "idx_on_stock_portfolio_id_recorded_at_3fff6867ab"
    t.index ["stock_portfolio_id"], name: "index_stock_portfolio_snapshots_on_stock_portfolio_id"
  end

  create_table "stock_portfolios", force: :cascade do |t|
    t.bigint "allocation_bucket_id"
    t.datetime "created_at", null: false
    t.boolean "default", default: false, null: false
    t.string "market", default: "us", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["allocation_bucket_id"], name: "index_stock_portfolios_on_allocation_bucket_id"
    t.index ["user_id", "default"], name: "index_stock_portfolios_on_user_id_and_default"
    t.index ["user_id"], name: "index_stock_portfolios_on_user_id"
  end

  create_table "stock_trades", force: :cascade do |t|
    t.decimal "cedear_ratio", precision: 10, scale: 4
    t.datetime "created_at", null: false
    t.datetime "executed_at", null: false
    t.text "notes"
    t.decimal "price_usd", precision: 20, scale: 8, null: false
    t.string "row_signature", null: false
    t.decimal "shares", precision: 20, scale: 8, null: false
    t.string "side", null: false
    t.bigint "stock_portfolio_id", null: false
    t.string "ticker", null: false
    t.decimal "total_value_usd", precision: 20, scale: 8, null: false
    t.datetime "updated_at", null: false
    t.index ["stock_portfolio_id", "executed_at"], name: "index_stock_trades_on_portfolio_id_and_executed_at"
    t.index ["stock_portfolio_id", "row_signature"], name: "index_stock_trades_on_portfolio_id_and_row_signature", unique: true
    t.index ["stock_portfolio_id"], name: "index_stock_trades_on_stock_portfolio_id"
  end

  create_table "sync_runs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "exchange_account_id", null: false
    t.datetime "ran_at", null: false
    t.datetime "updated_at", null: false
    t.index ["exchange_account_id", "ran_at"], name: "index_sync_runs_on_account_and_ran_at"
    t.index ["exchange_account_id"], name: "index_sync_runs_on_exchange_account_id"
  end

  create_table "trades", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "exchange_account_id", null: false
    t.string "exchange_reference_id", null: false
    t.datetime "executed_at", null: false
    t.decimal "fee", precision: 20, scale: 8
    t.decimal "net_amount", precision: 20, scale: 8, null: false
    t.string "position_id"
    t.jsonb "raw_payload", default: {}
    t.string "side", null: false
    t.string "symbol", null: false
    t.datetime "updated_at", null: false
    t.index ["exchange_account_id", "exchange_reference_id"], name: "index_trades_on_account_and_reference", unique: true
    t.index ["exchange_account_id", "executed_at"], name: "index_trades_on_exchange_account_id_and_executed_at"
    t.index ["exchange_account_id", "position_id"], name: "index_trades_on_account_and_position_id"
    t.index ["exchange_account_id"], name: "index_trades_on_exchange_account_id"
  end

  create_table "user_preferences", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.jsonb "value", null: false
    t.index ["user_id", "key"], name: "index_user_preferences_on_user_id_and_key", unique: true
    t.index ["user_id"], name: "index_user_preferences_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.string "email"
    t.text "gemini_api_key"
    t.string "password_digest"
    t.string "role", default: "user", null: false
    t.string "sync_interval"
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
  end

  create_table "watchlist_tickers", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ticker", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id", "ticker"], name: "index_watchlist_tickers_on_user_id_and_ticker", unique: true
    t.index ["user_id"], name: "index_watchlist_tickers_on_user_id"
  end

  add_foreign_key "allocation_buckets", "users"
  add_foreign_key "allocation_manual_entries", "allocation_buckets"
  add_foreign_key "allocation_manual_entries", "users"
  add_foreign_key "cedear_instruments", "users"
  add_foreign_key "companies", "users"
  add_foreign_key "custom_metric_definitions", "companies"
  add_foreign_key "custom_metric_values", "custom_metric_definitions"
  add_foreign_key "custom_metric_values", "earnings_reports"
  add_foreign_key "earnings_reports", "companies"
  add_foreign_key "exchange_accounts", "users"
  add_foreign_key "portfolios", "exchange_accounts", on_delete: :nullify
  add_foreign_key "portfolios", "users"
  add_foreign_key "position_trades", "positions"
  add_foreign_key "position_trades", "trades"
  add_foreign_key "positions", "exchange_accounts"
  add_foreign_key "solid_queue_blocked_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_claimed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_failed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_ready_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_recurring_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_scheduled_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "spot_accounts", "allocation_buckets", on_delete: :nullify
  add_foreign_key "spot_accounts", "users"
  add_foreign_key "spot_transactions", "spot_accounts"
  add_foreign_key "stock_analyses", "users"
  add_foreign_key "stock_portfolio_snapshots", "stock_portfolios"
  add_foreign_key "stock_portfolios", "allocation_buckets", on_delete: :nullify
  add_foreign_key "stock_portfolios", "users"
  add_foreign_key "stock_trades", "stock_portfolios"
  add_foreign_key "sync_runs", "exchange_accounts"
  add_foreign_key "trades", "exchange_accounts"
  add_foreign_key "user_preferences", "users"
  add_foreign_key "watchlist_tickers", "users"
end
