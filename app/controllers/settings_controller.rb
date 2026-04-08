# frozen_string_literal: true

class SettingsController < ApplicationController
  def show
    # Single settings page; sync_interval is the main setting for MVP
  end

  def update
    if current_user.update(settings_params)
      redirect_to settings_path, notice: "Settings saved."
    else
      render :show, status: :unprocessable_entity
    end
  end

  def update_ai_key
    api_key = params[:api_key].to_s.strip.presence
    if current_user.update(gemini_api_key: api_key)
      redirect_to settings_path, notice: "API key saved."
    else
      redirect_to settings_path, alert: "Could not save API key."
    end
  end

  def remove_ai_key
    current_user.update!(gemini_api_key: nil)
    redirect_to settings_path, notice: "AI Assistant key removed."
  end

  private

  def settings_params
    params.require(:user).permit(:sync_interval)
  end
end
