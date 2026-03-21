# frozen_string_literal: true

require "test_helper"

module Stocks
  class IolClientTest < ActiveSupport::TestCase
    setup do
      # Reset class-level token cache before each test to avoid cross-test contamination
      IolClient.token_cache = nil
    end

    # --- token fetch ---

    test "quote returns nil when credentials are missing" do
      IolClient.stub(:credentials, nil) do
        assert_nil IolClient.new.quote("AAPL")
      end
    end

    test "quote fetches a bearer token and returns the price" do
      token_response = mock_success('{"access_token":"tok123","token_type":"bearer"}')
      quote_response = mock_success('{"ultimoPrecio":15000.0}')
      http = build_http_double(quote_response)

      Net::HTTP.stub(:post, token_response) do
        # stub(:start, return_value, *block_args) — block_args are passed to the caller's block
        Net::HTTP.stub(:start, quote_response, http) do
          IolClient.stub(:credentials, { username: "u", password: "p" }) do
            result = IolClient.new.quote("AAPL")
            assert_equal BigDecimal("15000.0"), result
          end
        end
      end
    end

    test "quote returns nil when token endpoint fails" do
      Net::HTTP.stub(:post, mock_failure) do
        IolClient.stub(:credentials, { username: "u", password: "p" }) do
          assert_nil IolClient.new.quote("AAPL")
        end
      end
    end

    test "quote returns nil when quote endpoint returns non-success" do
      token_response = mock_success('{"access_token":"tok123"}')
      bad_quote = mock_failure
      http = build_http_double(bad_quote)

      Net::HTTP.stub(:post, token_response) do
        Net::HTTP.stub(:start, bad_quote, http) do
          IolClient.stub(:credentials, { username: "u", password: "p" }) do
            assert_nil IolClient.new.quote("AAPL")
          end
        end
      end
    end

    test "quote returns nil when ultimoPrecio is zero or absent" do
      token_response = mock_success('{"access_token":"tok123"}')
      quote_response = mock_success('{"ultimoPrecio":0}')
      http = build_http_double(quote_response)

      Net::HTTP.stub(:post, token_response) do
        Net::HTTP.stub(:start, quote_response, http) do
          IolClient.stub(:credentials, { username: "u", password: "p" }) do
            assert_nil IolClient.new.quote("AAPL")
          end
        end
      end
    end

    test "quote returns nil and logs on network error" do
      token_response = mock_success('{"access_token":"tok123"}')
      raise_socket_error = ->(*_) { raise SocketError, "connection refused" }

      Net::HTTP.stub(:post, token_response) do
        Net::HTTP.stub(:start, raise_socket_error) do
          IolClient.stub(:credentials, { username: "u", password: "p" }) do
            assert_nil IolClient.new.quote("AAPL")
          end
        end
      end
    end

    test "token is cached and not re-fetched on second call" do
      token_response = mock_success('{"access_token":"tok123"}')
      quote_response = mock_success('{"ultimoPrecio":1000.0}')
      http = build_http_double(quote_response)
      post_call_count = 0

      Net::HTTP.stub(:post, ->(*) { post_call_count += 1; token_response }) do
        Net::HTTP.stub(:start, quote_response, http) do
          IolClient.stub(:credentials, { username: "u", password: "p" }) do
            client = IolClient.new
            client.quote("AAPL")
            client.quote("MSFT")
          end
        end
      end

      assert_equal 1, post_call_count, "Token endpoint should only be called once"
    end

    private

    def mock_success(body)
      obj = Object.new
      obj.define_singleton_method(:is_a?) { |klass| klass == Net::HTTPSuccess }
      obj.define_singleton_method(:body) { body }
      obj
    end

    def mock_failure
      obj = Object.new
      obj.define_singleton_method(:is_a?) { |_klass| false }
      obj
    end

    # Returns a fake http object whose #request method yields the given response.
    # Used with stub(:start, response, http) so the block `{ |http| http.request(req) }` works.
    def build_http_double(response)
      obj = Object.new
      obj.define_singleton_method(:request) { |_req| response }
      obj
    end
  end
end
