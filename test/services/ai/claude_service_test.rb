# frozen_string_literal: true

require "test_helper"

class Ai::ClaudeServiceTest < ActiveSupport::TestCase
  setup do
    @service = Ai::ClaudeService.new(api_key: "sk-ant-test-key")
  end

  # ── Success ────────────────────────────────────────────────────────────────

  test "generate returns text from a single text block" do
    body = JSON.generate({ "content" => [ { "type" => "text", "text" => "Deep analysis here" } ] })
    stub_http(code: "200", body: body) do
      assert_equal "Deep analysis here", @service.generate(prompt: "Analyze AAPL")
    end
  end

  test "generate joins multiple text blocks" do
    body = JSON.generate({
      "content" => [
        { "type" => "text", "text" => "First part. " },
        { "type" => "tool_use", "name" => "web_search", "input" => {} },
        { "type" => "text", "text" => "Second part." }
      ]
    })
    stub_http(code: "200", body: body) do
      assert_equal "First part. Second part.", @service.generate(prompt: "Analyze AAPL")
    end
  end

  test "generate ignores non-text blocks" do
    body = JSON.generate({
      "content" => [
        { "type" => "tool_use", "name" => "web_search", "input" => { "query" => "AAPL price" } },
        { "type" => "tool_result", "content" => "Some result" },
        { "type" => "text", "text" => "Analysis complete." }
      ]
    })
    stub_http(code: "200", body: body) do
      assert_equal "Analysis complete.", @service.generate(prompt: "Analyze AAPL")
    end
  end

  test "generate passes system prompt and tools in request body" do
    resp_body    = JSON.generate({ "content" => [ { "type" => "text", "text" => "ok" } ] })
    captured     = nil
    ok_response  = stub_response(code: "200", body: resp_body)

    fake = Object.new
    fake.define_singleton_method(:use_ssl=)      { |_| }
    fake.define_singleton_method(:open_timeout=) { |_| }
    fake.define_singleton_method(:read_timeout=) { |_| }
    fake.define_singleton_method(:request)       { |req| captured = JSON.parse(req.body); ok_response }

    Net::HTTP.stub(:new, fake) do
      @service.generate(prompt: "test", system: "You are an analyst", tools: [ { "type" => "web_search_20260209" } ])
    end

    assert_equal "You are an analyst",             captured["system"]
    assert_equal [ { "type" => "web_search_20260209" } ], captured["tools"]
  end

  test "generate sets required headers" do
    resp_body       = JSON.generate({ "content" => [ { "type" => "text", "text" => "ok" } ] })
    captured        = {}
    ok_response     = stub_response(code: "200", body: resp_body)

    fake = Object.new
    fake.define_singleton_method(:use_ssl=)      { |_| }
    fake.define_singleton_method(:open_timeout=) { |_| }
    fake.define_singleton_method(:read_timeout=) { |_| }
    fake.define_singleton_method(:request) do |req|
      captured["x-api-key"]         = req["x-api-key"]
      captured["anthropic-version"] = req["anthropic-version"]
      captured["content-type"]      = req["content-type"]
      ok_response
    end

    Net::HTTP.stub(:new, fake) { @service.generate(prompt: "test") }

    assert_equal "sk-ant-test-key",  captured["x-api-key"]
    assert_equal "2023-06-01",       captured["anthropic-version"]
    assert_equal "application/json", captured["content-type"]
  end

  # ── Error responses ────────────────────────────────────────────────────────

  test "generate raises RateLimitError on 429" do
    stub_http(code: "429", body: "{}") do
      assert_raises(Ai::RateLimitError) { @service.generate(prompt: "test") }
    end
  end

  test "generate raises InvalidKeyError on 401" do
    stub_http(code: "401", body: "{}") do
      assert_raises(Ai::InvalidKeyError) { @service.generate(prompt: "test") }
    end
  end

  test "generate raises InvalidKeyError on 403" do
    stub_http(code: "403", body: "{}") do
      assert_raises(Ai::InvalidKeyError) { @service.generate(prompt: "test") }
    end
  end

  test "generate raises ServiceError on 400" do
    stub_http(code: "400", body: "bad request") do
      assert_raises(Ai::ServiceError) { @service.generate(prompt: "test") }
    end
  end

  test "generate raises ServiceError on 500" do
    stub_http(code: "500", body: "server error") do
      assert_raises(Ai::ServiceError) { @service.generate(prompt: "test") }
    end
  end

  test "generate raises ServiceError on empty body" do
    stub_http(code: "200", body: "") do
      assert_raises(Ai::ServiceError) { @service.generate(prompt: "test") }
    end
  end

  test "generate raises ServiceError when no text blocks present" do
    body = JSON.generate({ "content" => [ { "type" => "tool_use", "name" => "web_search" } ] })
    stub_http(code: "200", body: body) do
      assert_raises(Ai::ServiceError) { @service.generate(prompt: "test") }
    end
  end

  test "generate raises ServiceError on non-JSON body" do
    stub_http(code: "200", body: "not json") do
      assert_raises(Ai::ServiceError) { @service.generate(prompt: "test") }
    end
  end

  test "generate raises ServiceError on read timeout" do
    stub_http_timeout(Net::ReadTimeout) do
      assert_raises(Ai::ServiceError) { @service.generate(prompt: "test") }
    end
  end

  test "generate raises ServiceError on open timeout" do
    stub_http_timeout(Net::OpenTimeout) do
      assert_raises(Ai::ServiceError) { @service.generate(prompt: "test") }
    end
  end

  # ── WEB_SEARCH_TOOL constant ───────────────────────────────────────────────

  test "WEB_SEARCH_TOOL has expected structure" do
    tool = Ai::ClaudeService::WEB_SEARCH_TOOL
    assert_equal "web_search_20260209", tool["type"]
    assert_equal "web_search",          tool["name"]
    assert_equal 10,                    tool["max_uses"]
  end

  private

  def stub_response(code:, body:)
    res = Object.new
    res.define_singleton_method(:code) { code.to_s }
    res.define_singleton_method(:body) { body }
    res
  end

  def stub_http(code:, body:)
    response = stub_response(code: code, body: body)
    fake = Object.new
    fake.define_singleton_method(:use_ssl=)      { |_| }
    fake.define_singleton_method(:open_timeout=) { |_| }
    fake.define_singleton_method(:read_timeout=) { |_| }
    fake.define_singleton_method(:request)       { |_req| response }
    Net::HTTP.stub(:new, fake) { yield }
  end

  def stub_http_timeout(exception_class)
    fake = Object.new
    fake.define_singleton_method(:use_ssl=)      { |_| }
    fake.define_singleton_method(:open_timeout=) { |_| }
    fake.define_singleton_method(:read_timeout=) { |_| }
    fake.define_singleton_method(:request)       { |_req| raise exception_class, "timeout" }
    Net::HTTP.stub(:new, fake) { yield }
  end
end
