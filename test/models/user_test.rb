# frozen_string_literal: true

require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "admin defaults to false" do
    user = User.new(email: "test@example.com", password: "password")
    assert_equal false, user.admin
  end
end
