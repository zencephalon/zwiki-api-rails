Rails.application.routes.draw do
  # For details on the DSL available within this file, see http://guides.rubyonrails.org/routing.html
  resources :nodes
  resources :users do
    get 'me', to: 'users#me', on: :collection
  end
  # For details on the DSL available within this file, see http://guides.rubyonrails.org/routing.html
  post 'login', to: 'sessions#login'
  post 'register', to: 'sessions#register'
end
