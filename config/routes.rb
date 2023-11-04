Rails.application.routes.draw do
  # resources :quests
  put 'quests', to: 'quests#update'
  get 'quests', to: 'quests#show'
  # For details on the DSL available within this file, see http://guides.rubyonrails.org/routing.html
  resources :nodes
  resources :users do
    get 'me', to: 'users#me', on: :collection
  end
  # For details on the DSL available within this file, see http://guides.rubyonrails.org/routing.html
  post 'login', to: 'sessions#login'
  post 'register', to: 'sessions#register'

  get 'public/node/:slug', to: 'public#show'
  get 'public/index', to: 'public#index'
  get 'public/site_index', to: 'public#site_index'
  get 'public/root', to: 'public#root'
end
