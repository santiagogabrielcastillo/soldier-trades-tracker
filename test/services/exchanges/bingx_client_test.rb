# frozen_string_literal: true

require "test_helper"

module Exchanges
  class BingxClientTest < ActiveSupport::TestCase
    setup do
      @client = BingxClient.new(api_key: "test_key", api_secret: "test_secret")
    end

    test "signed_get raises ApiError for 429" do
      stub_http_response(code: "429", body: '{"msg":"rate limit"}', headers: { "Retry-After" => "60" }) do
        err = assert_raises(ApiError) { @client.signed_get("/path", "limit" => 1) }
        assert_match(/429/, err.message)
        assert_equal "429", err.response_code
        assert_equal 60, err.retry_after
      end
    end

    test "signed_get raises ApiError for 5xx" do
      stub_http_response(code: "502", body: "Bad Gateway") do
        err = assert_raises(ApiError) { @client.signed_get("/path", "limit" => 1) }
        assert_match(/502/, err.message)
        assert_equal "502", err.response_code
      end
    end

    test "signed_get raises ApiError for 200 with empty body" do
      stub_http_response(code: "200", body: "") do
        err = assert_raises(ApiError) { @client.signed_get("/path", "limit" => 1) }
        assert_match(/empty body/, err.message)
      end
    end

    test "signed_get raises ApiError for 200 with non-JSON body" do
      stub_http_response(code: "200", body: "<html>not json</html>") do
        err = assert_raises(ApiError) { @client.signed_get("/path", "limit" => 1) }
        assert_match(/non-JSON/, err.message)
      end
    end

    test "signed_get raises ApiError on timeout" do
      stub_http_timeout(Net::ReadTimeout) do
        err = assert_raises(ApiError) { @client.signed_get("/path", "limit" => 1) }
        assert_match(/timeout/, err.message)
      end
    end

    test "allows USDT and USDC trades by default (no kwarg)" do
      client = BingxClient.new(api_key: "k", api_secret: "s")
      assert client.send(:allowed_quote?, "BTC-USDT"), "USDT should be allowed by default"
      assert client.send(:allowed_quote?, "ETH-USDC"), "USDC should be allowed by default"
    end

    test "filters out USDC when allowed_quote_currencies is USDT only" do
      client = BingxClient.new(api_key: "k", api_secret: "s", allowed_quote_currencies: [ "USDT" ])
      assert client.send(:allowed_quote?, "BTC-USDT"), "USDT allowed"
      assert_not client.send(:allowed_quote?, "BTC-USDC"), "USDC not allowed"
    end

    test "falls back to default when allowed_quote_currencies is nil" do
      client = BingxClient.new(api_key: "k", api_secret: "s", allowed_quote_currencies: nil)
      assert client.send(:allowed_quote?, "BTC-USDT"), "USDT allowed via default"
      assert client.send(:allowed_quote?, "BTC-USDC"), "USDC allowed via default"
      assert_not client.send(:allowed_quote?, "BTC-BNB"), "non-stablecoin not in default whitelist"
    end

    test "case-insensitive quote extraction in allowed_quote?" do
      client = BingxClient.new(api_key: "k", api_secret: "s", allowed_quote_currencies: [ "USDT" ])
      assert client.send(:allowed_quote?, "BTC-usdt"), "lowercase quote should be normalized"
    end

    test "stablequote_pair? is an alias for allowed_quote?" do
      client = BingxClient.new(api_key: "k", api_secret: "s", allowed_quote_currencies: [ "USDT" ])
      assert_equal client.send(:allowed_quote?, "BTC-USDT"), client.send(:stablequote_pair?, "BTC-USDT")
      assert_equal client.send(:allowed_quote?, "BTC-USDC"), client.send(:stablequote_pair?, "BTC-USDC")
    end

    test "signed_get does not raise ApiError for other 4xx" do
      stub_http_response(code: "400", body: '{"msg":"bad request"}') do
        err = assert_raises(StandardError) { @client.signed_get("/path", "limit" => 1) }
        refute err.is_a?(ApiError), "Expected generic error, got ApiError: #{err.message}"
        assert_match(/400/, err.message)
      end
    end

    private

    def fake_response(code:, body:, headers: {})
      res = Object.new
      res.define_singleton_method(:code) { code.to_s }
      res.define_singleton_method(:body) { body }
      res.define_singleton_method(:[]) { |k| headers[k] }
      res
    end

    def stub_http_response(code:, body:, headers: {})
      response = fake_response(code: code, body: body, headers: headers)
      http = build_fake_http(response: response)
      Net::HTTP.stub(:new, http) { yield }
    end

    def stub_http_timeout(exception_klass)
      http = build_fake_http(raise_on_request: exception_klass.new("timeout"))
      Net::HTTP.stub(:new, http) { yield }
    end

    def build_fake_http(response: nil, raise_on_request: nil)
      fake = Object.new
      fake.define_singleton_method(:use_ssl=) { |_| }
      fake.define_singleton_method(:open_timeout=) { |_| }
      fake.define_singleton_method(:read_timeout=) { |_| }
      fake.define_singleton_method(:request) do |_req|
        raise raise_on_request if raise_on_request
        response
      end
      fake
    end
  end
end
