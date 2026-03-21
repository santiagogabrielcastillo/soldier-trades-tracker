# frozen_string_literal: true

require "test_helper"

module Stocks
  class MepRateFetcherTest < ActiveSupport::TestCase
    setup do
      # Clear cache between tests
      Rails.cache.delete("mep_rate")
    end

    test "returns BigDecimal from primary source" do
      mock_primary = mock_success('{"venta":1245.50}')

      Net::HTTP.stub(:get_response, mock_primary) do
        assert_equal BigDecimal("1245.5"), MepRateFetcher.call
      end
    end

    test "falls back to secondary source when primary fails" do
      call_count = 0
      responses = [
        mock_failure,
        mock_success('{"venta":1300.0}')
      ]

      Net::HTTP.stub(:get_response, ->(_) { responses[call_count].tap { call_count += 1 } }) do
        result = MepRateFetcher.call
        assert_equal BigDecimal("1300.0"), result
        assert_equal 2, call_count
      end
    end

    test "returns nil when both sources fail" do
      Net::HTTP.stub(:get_response, ->(_) { mock_failure }) do
        assert_nil MepRateFetcher.call
      end
    end

    test "returns nil when venta is zero" do
      Net::HTTP.stub(:get_response, mock_success('{"venta":0}')) do
        assert_nil MepRateFetcher.call
      end
    end

    test "returns nil on network error from all sources" do
      Net::HTTP.stub(:get_response, ->(_) { raise SocketError, "connection refused" }) do
        assert_nil MepRateFetcher.call
      end
    end

    test "caches successful result for subsequent calls" do
      call_count = 0
      with_memory_cache do
        Net::HTTP.stub(:get_response, ->(_) { call_count += 1; mock_success('{"venta":1245.5}') }) do
          MepRateFetcher.call
          MepRateFetcher.call
        end
      end

      assert_equal 1, call_count, "HTTP should only be called once due to caching"
    end

    test "does not cache nil result" do
      call_count = 0
      with_memory_cache do
        Net::HTTP.stub(:get_response, ->(_) { call_count += 1; mock_failure }) do
          MepRateFetcher.call
          MepRateFetcher.call
        end
      end

      assert call_count > 1, "Should retry when previous result was nil"
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

    # Temporarily swaps in a real MemoryStore so Rails.cache.fetch actually caches.
    # The test environment uses :null_store by default.
    def with_memory_cache
      original = Rails.cache
      Rails.cache = ActiveSupport::Cache::MemoryStore.new
      yield
    ensure
      Rails.cache = original
    end
  end
end
