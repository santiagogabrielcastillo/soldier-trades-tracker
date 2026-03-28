Rails.application.routes.draw do
  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  get "up" => "rails/health#show", as: :rails_health_check

  get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest

  get "login", to: "sessions#new", as: :login
  post "login", to: "sessions#create"
  delete "logout", to: "sessions#destroy", as: :logout

  resources :users, only: %i[new create]

  root "dashboards#show"

  resource :settings, only: %i[show update], controller: "settings"

  resources :exchange_accounts, only: %i[index new create destroy edit update] do
    member do
      post :sync
    end
    resources :manual_trades, only: %i[new create edit update destroy]
  end
  resources :trades, only: :index
  patch "user_preferences/trades_index_columns", to: "user_preferences#update_trades_index_columns", as: :user_preferences_trades_index_columns
  resources :portfolios do
    member do
      post :set_default
    end
  end

  get "spot", to: "spot#index", as: :spot
  post "spot/import", to: "spot#import", as: :spot_import
  post "spot/transactions", to: "spot#create", as: :spot_transactions

  get "stocks", to: "stocks#index", as: :stocks
  post "stocks/trades", to: "stocks#create", as: :stocks_trades
  post "stocks/snapshots", to: "stocks#record_snapshot", as: :stocks_snapshots
  delete "stocks/snapshots/:id", to: "stocks#destroy_snapshot", as: :stocks_snapshot
  post "stocks/sync_fundamentals", to: "stocks#sync_fundamentals", as: :stocks_sync_fundamentals
  post "stocks/watchlist/sync",    to: "stocks#sync_watchlist",    as: :stocks_watchlist_sync
  post "stocks/watchlist",         to: "stocks#add_to_watchlist",  as: :stocks_watchlist
  delete "stocks/watchlist/:id",   to: "stocks#remove_from_watchlist", as: :stocks_watchlist_item

  resources :stock_portfolios, only: %i[index new create edit update]

  resources :cedear_instruments, only: %i[index new create edit update destroy] do
    collection do
      get :lookup
    end
  end

  resource :allocation, only: [:show]
  patch "allocation/assign_stock_portfolio/:id", to: "allocations#assign_stock_portfolio", as: :allocation_assign_stock_portfolio
  patch "allocation/assign_spot_account/:id",   to: "allocations#assign_spot_account",    as: :allocation_assign_spot_account
  resources :allocation_buckets,        only: %i[create update destroy]
  resources :allocation_manual_entries, only: %i[create update destroy]
end
