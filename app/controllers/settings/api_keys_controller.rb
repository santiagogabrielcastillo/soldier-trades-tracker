# frozen_string_literal: true

module Settings
  class ApiKeysController < ApplicationController
    PROVIDERS = UserApiKey::PROVIDERS.freeze

    def index
      @keys_by_provider = current_user.user_api_keys.index_by(&:provider)
    end

    def upsert
      provider = params[:provider].to_s
      key      = params[:key].to_s.strip
      secret   = params[:secret].to_s.strip.presence

      unless PROVIDERS.include?(provider) && key.present?
        redirect_to settings_api_keys_path, alert: t("flash.api_key_invalid") and return
      end

      row = current_user.user_api_keys.find_or_initialize_by(provider: provider)
      row.key    = key
      row.secret = secret

      if row.save
        redirect_to settings_api_keys_path, notice: t("flash.api_key_saved", provider: provider.capitalize)
      else
        redirect_to settings_api_keys_path, alert: t("flash.api_key_save_failed")
      end
    end

    def destroy
      current_user.user_api_keys.find_by(provider: params[:provider])&.destroy
      redirect_to settings_api_keys_path, notice: t("flash.api_key_removed")
    end
  end
end
