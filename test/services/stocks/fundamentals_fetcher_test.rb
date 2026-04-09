# frozen_string_literal: true

require "test_helper"

module Stocks
  class FundamentalsFetcherTest < ActiveSupport::TestCase
    FIXTURE_HTML = File.read(
      Rails.root.join("test/fixtures/files/finviz_quote.html")
    ).freeze

    test "returns empty hash for blank tickers" do
      assert_equal({}, FundamentalsFetcher.call(tickers: []))
    end

    test "parses existing metrics from snapshot table" do
      result = fetch_with_fixture("AAPL")

      assert_in_delta 28.5,   result.pe.to_f,         0.01
      assert_in_delta 25.1,   result.fwd_pe.to_f,     0.01
      assert_in_delta 2.30,   result.peg.to_f,         0.01
      assert_in_delta 7.50,   result.ps.to_f,          0.01
      assert_in_delta 30.2,   result.pfcf.to_f,        0.01
      assert_in_delta 25.31,  result.net_margin.to_f,  0.01
      assert_in_delta 147.25, result.roe.to_f,         0.01
      assert_in_delta 55.10,  result.roic.to_f,        0.01
      assert_in_delta 1.87,   result.debt_eq.to_f,     0.01
      assert_in_delta 2.02,   result.sales_5y.to_f,    0.01
      assert_in_delta 4.87,   result.sales_qq.to_f,    0.01
    end

    test "parses ev_ebitda from snapshot table" do
      result = fetch_with_fixture("AAPL")

      assert_in_delta 22.10, result.ev_ebitda.to_f, 0.01
    end

    test "parses sector from screener link" do
      result = fetch_with_fixture("AAPL")

      assert_equal "Technology", result.sector
    end

    test "parses industry from screener link" do
      result = fetch_with_fixture("AAPL")

      assert_equal "Consumer Electronics", result.industry
    end

    test "returns nil for sector when link not present" do
      html = "<html><body><table class='snapshot-table2'><tr><td>P/E</td><td>10.0</td></tr></table></body></html>"
      result = fetch_with_html("AAPL", html)

      assert_nil result.sector
    end

    test "returns nil for ev_ebitda when not in table" do
      html = "<html><body><table class='snapshot-table2'><tr><td>P/E</td><td>28.5</td></tr></table></body></html>"
      result = fetch_with_html("AAPL", html)

      assert_nil result.ev_ebitda
    end

    test "returns nil when snapshot table is missing" do
      html = "<html><body><p>Not found</p></body></html>"
      result_hash = nil
      fetcher = FundamentalsFetcher.new(["AAPL"])
      Net::HTTP.stub(:start, mock_start(html)) do
        result_hash = fetcher.call
      end
      assert_nil result_hash["AAPL"]
    end

    private

    def fetch_with_fixture(ticker)
      fetch_with_html(ticker, FIXTURE_HTML)
    end

    def fetch_with_html(ticker, html)
      fetcher = FundamentalsFetcher.new([ticker])
      result = nil
      Net::HTTP.stub(:start, mock_start(html)) do
        result = fetcher.call
      end
      result[ticker]
    end

    def mock_start(body)
      res = Object.new
      res.define_singleton_method(:is_a?) { |klass| klass == Net::HTTPSuccess }
      res.define_singleton_method(:body)  { body }
      http = Object.new
      http.define_singleton_method(:request) { |_req| res }
      ->(_host, _port, **_opts, &block) { block.call(http) }
    end
  end
end
