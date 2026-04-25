# frozen_string_literal: true

class SessionsController < ApplicationController
  skip_before_action :require_login, only: %i[new create]

  def new
    @user = User.new
  end

  def create
    user = User.find_by(email: params[:email].to_s.strip.downcase)
    if user&.authenticate(params[:password]) && user.active?
      reset_session
      session[:user_id] = user.id
      redirect_to root_path, notice: t("flash.signed_in")
    else
      flash.now[:alert] = t("flash.invalid_credentials")
      @user = User.new(email: params[:email])
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    reset_session
    redirect_to login_path, notice: t("flash.signed_out")
  end
end
