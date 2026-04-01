require "test_helper"

class RackAttackTest < ActionDispatch::IntegrationTest
  setup do
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new

    # Re-register throttles for these tests since they are disabled in test env
    Rack::Attack.throttle("login/ip", limit: 10, period: 1.minute) do |req|
      req.ip if req.path == "/login" && req.post?
    end

    Rack::Attack.throttle("login/email", limit: 5, period: 1.minute) do |req|
      if req.path == "/login" && req.post?
        req.params["email"].to_s.downcase.presence
      end
    end
  end

  teardown do
    Rack::Attack.throttles.delete("login/ip")
    Rack::Attack.throttles.delete("login/email")
  end

  test "allows normal login attempts" do
    post login_url, params: { email: "test@example.com", password: "wrong" }
    assert_not_equal 429, response.status
  end

  test "throttles excessive login attempts by IP" do
    11.times do
      post login_url,
           params: { email: "attacker@example.com", password: "wrong" },
           headers: { "REMOTE_ADDR" => "1.2.3.4" }
    end
    assert_response 429
  end
end
