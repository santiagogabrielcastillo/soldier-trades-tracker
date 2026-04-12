# frozen_string_literal: true

require "test_helper"

class CustomMetricDefinitionTest < ActiveSupport::TestCase
  setup do
    @company = users(:one).companies.create!(ticker: "TEST", name: "Test Co")
  end

  test "valid definition saves" do
    defn = @company.custom_metric_definitions.build(name: "ARR", data_type: "number")
    assert defn.valid?, defn.errors.full_messages.inspect
  end

  test "name is required" do
    defn = @company.custom_metric_definitions.build(name: nil, data_type: "number")
    assert_not defn.valid?
    assert_includes defn.errors[:name], "can't be blank"
  end

  test "data_type must be number, percentage, or text" do
    defn = @company.custom_metric_definitions.build(name: "X", data_type: "invalid")
    assert_not defn.valid?
    assert_includes defn.errors[:data_type], "is not included in the list"
  end

  test "data_type is required" do
    defn = @company.custom_metric_definitions.build(name: "X", data_type: nil)
    assert_not defn.valid?
    assert_includes defn.errors[:data_type], "can't be blank"
  end

  test "name is unique per company" do
    @company.custom_metric_definitions.create!(name: "ARR", data_type: "number")
    duplicate = @company.custom_metric_definitions.build(name: "ARR", data_type: "text")
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:name], "has already been taken"
  end

  test "same name allowed for different companies" do
    @company.custom_metric_definitions.create!(name: "ARR", data_type: "number")
    other = users(:one).companies.create!(ticker: "NFLX", name: "Netflix")
    defn = other.custom_metric_definitions.build(name: "ARR", data_type: "number")
    assert defn.valid?
  end

  test "all three valid data types" do
    %w[number percentage text].each do |dt|
      defn = @company.custom_metric_definitions.build(name: dt, data_type: dt)
      assert defn.valid?, "Expected #{dt} to be valid"
    end
  end
end
