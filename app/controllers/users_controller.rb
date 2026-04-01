# frozen_string_literal: true

class UsersController < ApplicationController
  skip_before_action :require_login, only: %i[new create]

  def new
    @user = User.new
  end

  def create
    raise ActionController::RoutingError, "Not Found" unless registration_open?

    @user = User.new(user_params)
    if @user.save
      reset_session
      session[:user_id] = @user.id
      redirect_to root_path, notice: "Account created. Welcome!"
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def registration_open?
    ENV["REGISTRATION_OPEN"] == "true"
  end

  def user_params
    params.require(:user).permit(:email, :password, :password_confirmation, :sync_interval)
  end
end
