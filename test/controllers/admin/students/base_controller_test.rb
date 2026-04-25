require "test_helper"

class Admin::Students::RoutingTest < ActionDispatch::IntegrationTest
  test "routes to admin students trades index" do
    assert_routing(
      { path: "/admin/students/1/trades", method: :get },
      { controller: "admin/students/trades", action: "index", student_id: "1" }
    )
  end

  test "routes to admin audit log" do
    assert_routing(
      { path: "/admin/audit_log", method: :get },
      { controller: "admin/audit_log", action: "show" }
    )
  end
end
