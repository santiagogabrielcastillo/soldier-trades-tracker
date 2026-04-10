# frozen_string_literal: true

class Admin::InviteCodeController < Admin::BaseController
  def show
    @invite_code = InviteCode.current
  end

  def create
    expires_at = Time.zone.parse(params[:expires_at].to_s.presence || "")
    if expires_at.nil? || expires_at <= Time.current
      redirect_to admin_invite_code_path, alert: "Please provide a valid future expiry date." and return
    end

    InviteCode.rotate!(expires_at: expires_at)
    redirect_to admin_invite_code_path, notice: "Invite code rotated successfully."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to admin_invite_code_path, alert: "Could not rotate code: #{e.message}"
  end
end
