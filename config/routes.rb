Rails.application.routes.draw do
  resources :questlogs
  # resources :quests
  put 'quests', to: 'quests#update'
  get 'quests', to: 'quests#show'
  # For details on the DSL available within this file, see http://guides.rubyonrails.org/routing.html
  get 'nodes/search', to: 'nodes#search'
  get 'nodes/full_search_with_summary', to: 'nodes#full_search_with_summary'
  resources :nodes
  post 'nodes/:id/append', to: 'nodes#append'
  post 'nodes/:id/magic_append', to: 'nodes#magic_append'

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
