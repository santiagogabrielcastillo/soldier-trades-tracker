ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "minitest/mock"
require "mocha/minitest"

# Allow Minitest-style `.stub(:method, value) { }` syntax on Mocha's any_instance
# by aliasing it to Mocha's `.stubs(:method).returns(value)` with a block wrapper.
Mocha::ClassMethods::AnyInstance.class_eval do
  def stub(name, val, &block)
    stubs(name).returns(val)
    block.call(self)
  ensure
    unstub(name)
  end
end

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
  end
end
