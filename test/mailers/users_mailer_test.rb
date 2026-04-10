# frozen_string_literal: true

require "test_helper"

class UsersMailerTest < ActionMailer::TestCase
  include Rails.application.routes.url_helpers

  setup do
    @user = users(:one)
    @user.update!(password: "password")
    @token = @user.generate_token_for(:password_reset)
  end

  test "password_reset delivers to correct recipient" do
    mail = UsersMailer.password_reset(@user, @token)
    assert_equal [ @user.email ], mail.to
  end

  test "password_reset has correct subject" do
    mail = UsersMailer.password_reset(@user, @token)
    assert_equal "Reset your password", mail.subject
  end

  test "password_reset HTML body contains reset link" do
    mail = UsersMailer.password_reset(@user, @token)
    assert_match edit_password_reset_url(token: @token, host: "www.example.com"), mail.body.encoded
  end

  test "password_reset text body contains reset link" do
    mail = UsersMailer.password_reset(@user, @token)
    assert_match edit_password_reset_url(token: @token, host: "www.example.com"), mail.text_part.body.encoded
  end
end
