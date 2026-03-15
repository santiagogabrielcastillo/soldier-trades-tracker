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

  resources :exchange_accounts, only: %i[index new create destroy] do
    member do
      post :sync
    end
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
end
