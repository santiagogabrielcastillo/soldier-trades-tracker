# frozen_string_literal: true

require "test_helper"

class Ai::GeminiServiceTest < ActiveSupport::TestCase
  setup do
    @service = Ai::GeminiService.new(api_key: "AIzaTestKey")
  end

  test "generate returns response text on success" do
    body = JSON.generate({
      "candidates" => [
        { "content" => { "parts" => [ { "text" => "Hello from Gemini" } ] } }
      ]
    })
    stub_http_response(code: "200", body: body) do
      result = @service.generate(prompt: "Say hello")
      assert_equal "Hello from Gemini", result
    end
  end

  test "generate raises RateLimitError on 429" do
    body = JSON.generate({ "error" => { "code" => 429, "message" => "Resource exhausted" } })
    stub_http_response(code: "429", body: body) do
      assert_raises(Ai::RateLimitError) { @service.generate(prompt: "test") }
    end
  end

  test "generate raises InvalidKeyError on 401" do
    body = JSON.generate({ "error" => { "code" => 401, "message" => "API key not valid" } })
    stub_http_response(code: "401", body: body) do
      assert_raises(Ai::InvalidKeyError) { @service.generate(prompt: "test") }
    end
  end

  test "generate raises InvalidKeyError on 403" do
    body = JSON.generate({ "error" => { "code" => 403, "message" => "Forbidden" } })
    stub_http_response(code: "403", body: body) do
      assert_raises(Ai::InvalidKeyError) { @service.generate(prompt: "test") }
    end
  end

  test "generate raises ServiceError on 400" do
    body = JSON.generate({ "error" => { "code" => 400, "message" => "Bad Request" } })
    stub_http_response(code: "400", body: body) do
      assert_raises(Ai::ServiceError) { @service.generate(prompt: "test") }
    end
  end

  test "generate raises ServiceError on 500" do
    stub_http_response(code: "500", body: "Internal Server Error") do
      assert_raises(Ai::ServiceError) { @service.generate(prompt: "test") }
    end
  end

  test "generate raises ServiceError on empty body" do
    stub_http_response(code: "200", body: "") do
      assert_raises(Ai::ServiceError) { @service.generate(prompt: "test") }
    end
  end

  test "generate raises ServiceError on timeout" do
    stub_http_timeout(Net::ReadTimeout) do
      assert_raises(Ai::ServiceError) { @service.generate(prompt: "test") }
    end
  end

  private

  def fake_response(code:, body:)
    res = Object.new
    res.define_singleton_method(:code) { code.to_s }
    res.define_singleton_method(:body) { body }
    res
  end

  def stub_http_response(code:, body:)
    response = fake_response(code: code, body: body)
    fake = Object.new
    fake.define_singleton_method(:use_ssl=) { |_| }
    fake.define_singleton_method(:open_timeout=) { |_| }
    fake.define_singleton_method(:read_timeout=) { |_| }
    fake.define_singleton_method(:request) { |_req| response }
    Net::HTTP.stub(:new, fake) { yield }
  end

  def stub_http_timeout(exception_klass)
    fake = Object.new
    fake.define_singleton_method(:use_ssl=) { |_| }
    fake.define_singleton_method(:open_timeout=) { |_| }
    fake.define_singleton_method(:read_timeout=) { |_| }
    fake.define_singleton_method(:request) { |_req| raise exception_klass.new("timeout") }
    Net::HTTP.stub(:new, fake) { yield }
  end
end
