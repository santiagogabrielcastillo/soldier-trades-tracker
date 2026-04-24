# frozen_string_literal: true

class SettingsController < ApplicationController
  def show
  end

  def update
    if current_user.update(settings_params)
      redirect_to settings_path, notice: t("flash.settings_saved")
    else
      render :show, status: :unprocessable_entity
    end
  end

  private

  def settings_params
    params.require(:user).permit(:sync_interval)
  end
end
