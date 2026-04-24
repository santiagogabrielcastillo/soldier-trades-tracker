# frozen_string_literal: true

class UsersController < ApplicationController
  skip_before_action :require_login, only: %i[new create]

  def new
    @user = User.new
  end

  def create
    @user = User.new(user_params)
    invite = InviteCode.current

    unless invite&.valid_for_registration? && ActiveSupport::SecurityUtils.secure_compare(
      params[:invite_code].to_s, invite.code
    )
      flash.now[:alert] = t("flash.invalid_invite_code")
      render :new, status: :unprocessable_entity and return
    end

    if @user.save
      reset_session
      session[:user_id] = @user.id
      redirect_to root_path, notice: t("flash.account_created")
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def user_params
    params.require(:user).permit(:email, :password, :password_confirmation, :sync_interval)
  end
end
