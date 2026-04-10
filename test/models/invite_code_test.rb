# frozen_string_literal: true

require "test_helper"

class InviteCodeTest < ActiveSupport::TestCase
  test "current returns non-expired code" do
    code = invite_codes(:valid)
    assert_equal code, InviteCode.current
  end

  test "current returns nil when only expired code exists" do
    InviteCode.delete_all
    InviteCode.insert!({ code: "expiredcode1234567890abcdefgh", expires_at: 1.day.ago, created_at: Time.current, updated_at: Time.current })
    assert_nil InviteCode.current
  end

  test "current returns nil when table is empty" do
    InviteCode.delete_all
    assert_nil InviteCode.current
  end

  test "valid_for_registration? is true for non-expired code" do
    code = invite_codes(:valid)
    assert code.valid_for_registration?
  end

  test "valid_for_registration? is false for expired code" do
    code = InviteCode.new(code: "abc", expires_at: 1.day.ago)
    assert_not code.valid_for_registration?
  end

  test "rotate! creates a code when none exists" do
    InviteCode.delete_all
    new_expires = 7.days.from_now

    new_code = InviteCode.rotate!(expires_at: new_expires)

    assert_equal 1, InviteCode.count
    assert new_code.code.length >= 16
    assert_in_delta new_expires.to_i, new_code.expires_at.to_i, 1
  end

  test "rotate! updates the existing code and keeps exactly one row" do
    old_code = invite_codes(:valid)
    old_value = old_code.code

    new_code = InviteCode.rotate!(expires_at: 14.days.from_now)

    assert_equal 1, InviteCode.count
    assert_equal old_code.id, new_code.id, "Should reuse the same row (update, not insert)"
    assert_not_equal old_value, new_code.code, "Code value should be regenerated"
  end

  test "rotate! rolls back if validation fails" do
    InviteCode.delete_all
    assert_raises(ActiveRecord::RecordInvalid) do
      InviteCode.rotate!(expires_at: 1.day.ago) # past expiry fails validation on create
    end
    assert_equal 0, InviteCode.count
  end

  test "validates presence of code" do
    code = InviteCode.new(expires_at: 1.day.from_now)
    assert_not code.valid?
    assert_includes code.errors[:code], "can't be blank"
  end

  test "validates expires_at must be in the future on create" do
    code = InviteCode.new(code: "someuniquecode12345678", expires_at: 1.hour.ago)
    assert_not code.valid?
    assert code.errors[:expires_at].any?
  end

  test "expires_at future validation does not fire on update" do
    code = invite_codes(:valid)
    # Travel to future so code is now expired
    travel_to 2.years.from_now do
      code.code = "updatedcode12345678901"
      assert code.valid?, "Should allow updating a now-expired record"
    end
  end
end
