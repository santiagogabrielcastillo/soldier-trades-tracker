# frozen_string_literal: true

class UsersMailer < ApplicationMailer
  # TODO: set a real sender in ApplicationMailer default from: once a domain is configured
  def password_reset(user, token)
    @user = user
    @token = token
    @reset_url = edit_password_reset_url(token: token)
    mail(to: @user.email, subject: "Reset your password")
  end
end
