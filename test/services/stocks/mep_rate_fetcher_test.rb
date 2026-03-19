# frozen_string_literal: true

require "test_helper"

module Stocks
  class MepRateFetcherTest < ActiveSupport::TestCase
    test "returns BigDecimal when API responds with valid venta" do
      response_body = '{"venta":1245.50,"compra":1240.00}'
      mock_response = Minitest::Mock.new
      mock_response.expect(:is_a?, true, [ Net::HTTPSuccess ])
      mock_response.expect(:body, response_body)

      Net::HTTP.stub(:get_response, mock_response) do
        result = MepRateFetcher.call
        assert_equal BigDecimal("1245.5"), result
      end
    end

    test "returns nil when venta is zero" do
      response_body = '{"venta":0,"compra":0}'
      mock_response = Minitest::Mock.new
      mock_response.expect(:is_a?, true, [ Net::HTTPSuccess ])
      mock_response.expect(:body, response_body)

      Net::HTTP.stub(:get_response, mock_response) do
        result = MepRateFetcher.call
        assert_nil result
      end
    end

    test "returns nil on non-success HTTP response" do
      mock_response = Minitest::Mock.new
      mock_response.expect(:is_a?, false, [ Net::HTTPSuccess ])

      Net::HTTP.stub(:get_response, mock_response) do
        result = MepRateFetcher.call
        assert_nil result
      end
    end

    test "returns nil on network error" do
      Net::HTTP.stub(:get_response, ->(_) { raise SocketError, "connection refused" }) do
        result = MepRateFetcher.call
        assert_nil result
      end
    end
  end
end
