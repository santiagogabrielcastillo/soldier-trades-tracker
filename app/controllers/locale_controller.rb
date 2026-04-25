# frozen_string_literal: true

class LocaleController < ApplicationController
  def update
    locale = params[:locale].to_s
    locale = I18n.default_locale.to_s unless I18n.available_locales.map(&:to_s).include?(locale)

    pref = current_user.user_preferences.find_or_initialize_by(key: "locale")
    pref.value = locale
    pref.save!

    redirect_back fallback_location: root_path, notice: t("flash.language_changed")
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotSaved => e
    redirect_back fallback_location: root_path, alert: t("flash.language_change_failed", default: "Failed to update language preference. Please try again.")
  end
end
