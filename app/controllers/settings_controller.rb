# frozen_string_literal: true

class SettingsController < ApplicationController
  def show
    @ai_provider = Ai::ProviderForUser.new(current_user)
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
    if api_key
      record = current_user.user_api_keys.find_or_initialize_by(provider: "gemini")
      record.key = api_key
      if record.save
        redirect_to settings_path, notice: "API key saved."
      else
        redirect_to settings_path, alert: "Could not save API key."
      end
    else
      redirect_to settings_path, alert: "Could not save API key."
    end
  end

  def remove_ai_key
    current_user.user_api_keys.where(provider: "gemini").destroy_all
    redirect_to settings_path, notice: "AI Assistant key removed."
  end

  private

  def settings_params
    params.require(:user).permit(:sync_interval)
  end
end
