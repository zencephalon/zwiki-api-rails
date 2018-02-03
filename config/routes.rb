Rails.application.routes.draw do
  resources :nodes
  resources :users
  # For details on the DSL available within this file, see http://guides.rubyonrails.org/routing.html
  post 'login', to: 'sessions#login'
end
