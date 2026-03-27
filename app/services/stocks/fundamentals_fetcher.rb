# frozen_string_literal: true

require "net/http"
require "uri"

module Stocks
  # Scrapes fundamental valuation ratios from Finviz's public quote page.
  # No API key required. Politely rate-limited between requests.
  #
  # Metrics: P/E, Fwd P/E, PEG, P/S, P/FCF, Profit Margin, ROE, ROI
  class FundamentalsFetcher
    FINVIZ_BASE      = "https://finviz.com/quote.ashx"
    USER_AGENT       = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    RATE_LIMIT_DELAY = 1.2 # seconds between requests

    FundamentalsData = Struct.new(
      :pe, :fwd_pe, :peg, :ps, :pfcf, :net_margin, :roe, :roic,
      :debt_eq, :sales_5y, :sales_qq,
      keyword_init: true
    )

    def self.call(tickers:)
      new(tickers).call
    end

    def initialize(tickers)
      @tickers = tickers.map(&:upcase).uniq
    end

    def call
      return {} if @tickers.empty?

      result = {}
      @tickers.each_with_index do |ticker, i|
        sleep(RATE_LIMIT_DELAY) if i > 0
        data = fetch_for(ticker)
        result[ticker] = data if data
      end
      result
    end

    private

    def fetch_for(ticker)
      uri = URI("#{FINVIZ_BASE}?t=#{URI.encode_uri_component(ticker)}&p=d")

      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
        req = Net::HTTP::Get.new(uri)
        req["User-Agent"]      = USER_AGENT
        req["Accept-Language"] = "en-US,en;q=0.9"
        req["Accept"]          = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
        http.request(req)
      end

      return nil unless response.is_a?(Net::HTTPSuccess)

      parse_finviz(response.body, ticker)
    rescue => e
      Rails.logger.error("[Stocks::FundamentalsFetcher] #{ticker}: #{e.message}")
      nil
    end

    def parse_finviz(html, ticker)
      require "nokogiri"
      doc   = Nokogiri::HTML(html)
      table = doc.at_css("table.snapshot-table2")

      unless table
        Rails.logger.warn("[Stocks::FundamentalsFetcher] #{ticker}: snapshot table not found")
        return nil
      end

      # Look up each metric by finding its label TD and reading the next sibling TD.
      # This is robust against extra/header cells that would break each_slice(2).
      metrics = {}
      table.css("td").each do |td|
        label = td.text.strip
        next if label.empty?
        next_td = td.next_element
        metrics[label] = next_td.text.strip if next_td&.name == "td"
      end

      return nil if metrics.empty?

      Rails.logger.info("[Stocks::FundamentalsFetcher] #{ticker} metrics: #{metrics.slice('P/E','Fwd P/E','PEG','P/S','P/FCF','Profit Margin','ROE','ROIC','Debt/Eq','Sales Y/Y TTM','Sales Q/Q')}")

      FundamentalsData.new(
        pe:         decimal(metrics["P/E"]),
        fwd_pe:     decimal(metrics["Fwd P/E"]),
        peg:        decimal(metrics["PEG"]),
        ps:         decimal(metrics["P/S"]),
        pfcf:       decimal(metrics["P/FCF"]),
        net_margin: pct(metrics["Profit Margin"]),
        roe:        pct(metrics["ROE"]),
        roic:       pct(metrics["ROIC"]),
        debt_eq:    decimal(metrics["Debt/Eq"]),
        sales_5y:   pct(metrics["Sales Y/Y TTM"]),
        sales_qq:   pct(metrics["Sales Q/Q"])
      )
    end

    def decimal(val)
      return nil if val.nil? || val.strip.in?(["-", "", "N/A"])
      BigDecimal(val.to_s.gsub(",", ""))
    rescue ArgumentError, TypeError
      nil
    end

    def pct(val)
      return nil if val.nil? || val.strip.in?(["-", "", "N/A"])
      BigDecimal(val.to_s.delete("%,").strip)
    rescue ArgumentError, TypeError
      nil
    end
  end
end
