require "test_helper"

class AuditableTest < ActiveSupport::TestCase
  test "Trade responds to paper_trail methods after Auditable is included" do
    assert Trade.respond_to?(:paper_trail)
  end
end
