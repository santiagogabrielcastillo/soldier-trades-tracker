# frozen_string_literal: true

class UsersMailer < ApplicationMailer
  # TODO: set a real sender in ApplicationMailer default from: once a domain is configured
  def password_reset(user, token)
    @user = user
    @reset_url = edit_password_reset_url(token: token)
    mail(to: @user.email, subject: I18n.t("mailers.users_mailer.password_reset.subject"))
  end
end
