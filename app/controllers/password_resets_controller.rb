# frozen_string_literal: true

class PasswordResetsController < ApplicationController
  skip_before_action :require_login

  def new; end

  def create
    user = User.where(active: true).find_by(email: params[:email].to_s.strip.downcase)
    if user
      token = user.generate_token_for(:password_reset)
      UsersMailer.password_reset(user, token).deliver_now
    end
    # Same response whether or not the email matched — prevents account enumeration.
    redirect_to login_path, notice: "If that email is registered, you'll receive a reset link shortly."
  end

  def edit
    @token = params[:token]
    unless User.find_by_token_for(:password_reset, @token)
      redirect_to new_password_reset_path, alert: "Reset link is invalid or has expired."
    end
  end

  def update
    user = User.find_by_token_for(:password_reset, params[:token])
    unless user
      redirect_to new_password_reset_path, alert: "Reset link is invalid or has expired." and return
    end

    if user.update(password: params[:password], password_confirmation: params[:password_confirmation])
      redirect_to login_path, notice: "Password updated. Please sign in."
    else
      @token = params[:token]
      render :edit, status: :unprocessable_entity
    end
  end
end
