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

  # RESTful resources
  resources :positions, only: [:index]
  resource :portfolio, only: [:show], controller: "portfolios"
  resources :signals, only: [:index]
  resources :orders, only: [:index]
  resources :monitoring, only: [:index]
  resources :ai_evaluations, only: [:index], path: "ai-evaluations"

  # Screeners resource with custom collection actions
  resources :screeners, only: [] do
    collection do
      get :swing
      get :longterm
      post :run
      get :check_results, path: "check"
      post :start_ltp_updates, path: "ltp/start"
      post :stop_ltp_updates, path: "ltp/stop"
    end
  end

  # Trading mode resource (singleton)
  resource :trading_mode, only: [] do
    collection do
      post :toggle
    end
  end

  # About page
  get "about", to: "about#index", as: :about

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
