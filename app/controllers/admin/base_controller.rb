# frozen_string_literal: true

class Admin::BaseController < ApplicationController
  layout "admin"
  before_action :require_admin

  private

  def require_admin
    redirect_to root_path, alert: t("flash.not_authorized") and return unless current_user&.admin? || current_user&.super_admin?
  end

  def require_super_admin
    redirect_to root_path, alert: t("flash.not_authorized") and return unless current_user&.super_admin?
  end
end
