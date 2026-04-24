class ApplicationController < ActionController::Base
  include Pagy::Method

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  before_action :require_login
  around_action :set_locale

  helper_method :current_user

  private

  def current_user
    @current_user ||= User.where(active: true).find_by(id: session[:user_id]) if session[:user_id]
  end

  def require_login
    return if current_user

    redirect_to login_path, alert: t("flash.please_sign_in")
  end

  def set_locale(&action)
    locale = current_user&.user_preferences&.find_by(key: "locale")&.value
    locale = I18n.default_locale unless I18n.available_locales.map(&:to_s).include?(locale.to_s)
    I18n.with_locale(locale, &action)
  end
end
