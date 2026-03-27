# frozen_string_literal: true

require "test_helper"

module Stocks
  class MepRateFetcherTest < ActiveSupport::TestCase
    setup do
      # Clear cache between tests
      Rails.cache.delete("mep_rate")
    end

    # Sources: dolarhoy.com (scrape) → dolarapi.com (JSON) → argentinadatos.com (JSON)

    test "returns average of compra/venta from dolarhoy when scrape succeeds" do
      html = '<a href="/cotizaciondolarbolsa"><div class="compra">1200,00</div><div class="venta">1300,00</div></a>'
      Net::HTTP.stub(:get_response, mock_html_success(html)) do
        assert_equal BigDecimal("1250.0"), MepRateFetcher.call
      end
    end

    test "falls back to JSON source when dolarhoy scrape returns no data" do
      call_count = 0
      responses = [
        mock_html_success("<html></html>"),   # dolarhoy — no MEP link
        mock_success('{"venta":1300.0}')      # dolarapi.com
      ]

      Net::HTTP.stub(:get_response, ->(_) { responses[call_count].tap { call_count += 1 } }) do
        result = MepRateFetcher.call
        assert_equal BigDecimal("1300.0"), result
        assert_equal 2, call_count
      end
    end

    test "falls back to third source when dolarhoy and first JSON fail" do
      call_count = 0
      responses = [
        mock_failure,                         # dolarhoy
        mock_failure,                         # dolarapi.com
        mock_success('{"venta":1400.0}')      # argentinadatos.com
      ]

      Net::HTTP.stub(:get_response, ->(_) { responses[call_count].tap { call_count += 1 } }) do
        result = MepRateFetcher.call
        assert_equal BigDecimal("1400.0"), result
      end
    end

    test "returns nil when all sources fail" do
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

    test "caches successful result — second call makes no HTTP requests" do
      call_count = 0
      html = '<a href="/cotizaciondolarbolsa"><div class="compra">1245,50</div><div class="venta">1245,50</div></a>'
      with_memory_cache do
        Net::HTTP.stub(:get_response, ->(_) { call_count += 1; mock_html_success(html) }) do
          MepRateFetcher.call
          count_after_first = call_count
          MepRateFetcher.call
          assert_equal count_after_first, call_count, "Second call should use cache, not HTTP"
        end
      end
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

    def mock_html_success(html)
      mock_success(html)
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
