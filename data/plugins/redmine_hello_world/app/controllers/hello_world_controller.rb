# plugins/redmine_hello_world/app/controllers/hello_world_controller.rb
class HelloWorldController < ApplicationController
  # Redmine requires users to be logged in for most controllers by default.
  # If you want it public, you can use: skip_before_action :require_login
  before_action :require_login

  def index
    # Any controller logic could go here.
  end
end
