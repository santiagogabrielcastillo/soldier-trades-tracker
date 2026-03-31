# frozen_string_literal: true

require "test_helper"

module Exchanges
  module Binance
    class HttpClientTest < ActiveSupport::TestCase
      setup do
        @api_key    = "test_key"
        @api_secret = "test_secret"
      end

      test "uses fapi.binance.com when BINANCE_PROXY_URL is not set" do
        with_env("BINANCE_PROXY_URL" => nil, "BINANCE_PROXY_SECRET" => nil) do
          client = HttpClient.new(api_key: @api_key, api_secret: @api_secret)
          assert_equal "https://fapi.binance.com", client.base_url
        end
      end

      test "uses BINANCE_PROXY_URL when set" do
        with_env("BINANCE_PROXY_URL" => "https://binance-proxy.example.workers.dev",
                 "BINANCE_PROXY_SECRET" => "secret123") do
          client = HttpClient.new(api_key: @api_key, api_secret: @api_secret)
          assert_equal "https://binance-proxy.example.workers.dev", client.base_url
        end
      end

      test "adds X-Proxy-Token header when BINANCE_PROXY_SECRET is set" do
        with_env("BINANCE_PROXY_URL" => "https://binance-proxy.example.workers.dev",
                 "BINANCE_PROXY_SECRET" => "secret123") do
          captured_request = nil
          Net::HTTP.stub(:new, ->(_host, _port) {
            FakeHttp.new(on_request: ->(req) { captured_request = req },
                         body: '[{"symbol":"BTCUSDT"}]')
          }) do
            client = HttpClient.new(api_key: @api_key, api_secret: @api_secret)
            client.get("/fapi/v1/positionRisk") rescue nil
          end

          assert_not_nil captured_request
          assert_equal "secret123", captured_request["X-Proxy-Token"]
        end
      end

      test "does not add X-Proxy-Token header when BINANCE_PROXY_SECRET is not set" do
        with_env("BINANCE_PROXY_URL" => nil, "BINANCE_PROXY_SECRET" => nil) do
          captured_request = nil
          Net::HTTP.stub(:new, ->(_host, _port) {
            FakeHttp.new(on_request: ->(req) { captured_request = req },
                         body: '[{"symbol":"BTCUSDT"}]')
          }) do
            client = HttpClient.new(api_key: @api_key, api_secret: @api_secret)
            client.get("/fapi/v1/positionRisk") rescue nil
          end

          assert_not_nil captured_request
          assert_nil captured_request["X-Proxy-Token"]
        end
      end

      private

      def with_env(vars)
        original = vars.keys.each_with_object({}) { |k, h| h[k] = ENV[k] }
        vars.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
        yield
      ensure
        original.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
      end

      class FakeHttp
        def initialize(on_request:, body:)
          @on_request = on_request
          @body       = body
        end

        def use_ssl=(val); end
        def open_timeout=(val); end
        def read_timeout=(val); end

        def request(req)
          @on_request.call(req)
          FakeResponse.new(@body)
        end
      end

      class FakeResponse
        attr_reader :body
        def initialize(body); @body = body; end
        def code; "200"; end
        def [](key); nil; end
        def blank?; false; end
        def presence; body; end
      end
    end
  end
end
