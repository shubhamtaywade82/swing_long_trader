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
  get "positions", to: "dashboard#positions", as: :positions
  get "portfolio", to: "dashboard#portfolio", as: :portfolio
  get "signals", to: "dashboard#signals", as: :signals
  get "ai-evaluations", to: "dashboard#ai_evaluations", as: :ai_evaluations
  get "orders", to: "dashboard#orders", as: :orders
  get "monitoring", to: "dashboard#monitoring", as: :monitoring
  get "about", to: "about#index", as: :about
  get "screeners/swing", to: "dashboard#swing_screener", as: :swing_screener
  get "screeners/longterm", to: "dashboard#longterm_screener", as: :longterm_screener
  post "screeners/swing/run", to: "dashboard#run_swing_screener", as: :run_swing_screener
  post "screeners/longterm/run", to: "dashboard#run_longterm_screener", as: :run_longterm_screener
  get "screeners/check", to: "dashboard#check_screener_results", as: :check_screener_results
  post "dashboard/toggle_mode", to: "dashboard#toggle_trading_mode", as: :toggle_trading_mode

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
