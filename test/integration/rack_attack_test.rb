require "test_helper"

class RackAttackTest < ActionDispatch::IntegrationTest
  setup do
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
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
