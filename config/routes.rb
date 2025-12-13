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
  get "orders", to: "dashboard#orders", as: :orders
  get "monitoring", to: "dashboard#monitoring", as: :monitoring

  # ActionCable for live updates
  mount ActionCable.server => "/cable"
end
