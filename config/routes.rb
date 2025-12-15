# frozen_string_literal: true

Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Dashboard routes
  root "dashboard#index"
  get "dashboard", to: "dashboard#index", as: :dashboard

  # Page-specific controllers
  get "positions", to: "positions#index", as: :positions
  get "portfolio", to: "portfolios#show", as: :portfolio
  get "signals", to: "signals#index", as: :signals
  get "ai-evaluations", to: "ai_evaluations#index", as: :ai_evaluations
  get "orders", to: "orders#index", as: :orders
  get "monitoring", to: "monitoring#index", as: :monitoring
  get "about", to: "about#index", as: :about

  # Screener routes
  get "screeners/swing", to: "screeners#swing", as: :swing_screener
  get "screeners/longterm", to: "screeners#longterm", as: :longterm_screener
  post "screeners/:type/run", to: "screeners#run", as: :run_screener, constraints: { type: /swing|longterm/ }
  get "screeners/check", to: "screeners#check_results", as: :check_screener_results
  post "screeners/ltp/start", to: "screeners#start_ltp_updates", as: :start_ltp_updates
  post "screeners/ltp/stop", to: "screeners#stop_ltp_updates", as: :stop_ltp_updates

  # Trading mode toggle
  post "trading_mode/toggle", to: "trading_mode#toggle", as: :toggle_trading_mode

  # ActionCable for live updates
  mount ActionCable.server => "/cable"

  # Admin routes for Solid Queue monitoring
  namespace :admin do
    resources :solid_queue, only: %i[index show] do
      member do
        post :retry_failed
        delete :delete_job
        delete :delete_failed
        post :unqueue_job
      end
      collection do
        delete :clear_finished
        post :create_job
        post :pause_queue
        post :unpause_queue
        post :bulk_delete
        post :bulk_unqueue
      end
    end
  end
end
