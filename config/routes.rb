Rails.application.routes.draw do
  root "home#index"

  resources :scans, only: :create

  namespace :admin do
    resources :qr_codes, only: %i[new create]
    resources :outlaw_cards, only: %i[index create]
  end
end
