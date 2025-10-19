# plugins/redmine_hello_world/config/routes.rb
# This mounts /hello_world to HelloWorldController#index
Rails.application.routes.draw do
  get 'hello_world', to: 'hello_world#index'
end
