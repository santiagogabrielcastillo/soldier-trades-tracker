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
      :debt_eq, :sales_5y, :sales_qq, :sector, :industry, :ev_ebitda,
      :eps_next_y, :eps_next_y_pct,
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
      # "EPS next Y" appears twice (dollar value and % growth), so collect both separately.
      metrics = {}
      eps_next_y_values = []
      table.css("td").each do |td|
        label = td.text.strip
        next if label.empty?
        next_td = td.next_element
        next unless next_td&.name == "td"
        val = next_td.text.strip
        if label == "EPS next Y"
          eps_next_y_values << val
        else
          metrics[label] = val
        end
      end

      return nil if metrics.empty?

      # Classify EPS next Y values by format: percentage values end with "%"
      eps_next_y_dollar = eps_next_y_values.reject { |v| v.end_with?("%") }.first
      eps_next_y_pct    = eps_next_y_values.find    { |v| v.end_with?("%") }

      Rails.logger.info("[Stocks::FundamentalsFetcher] #{ticker} metrics: #{metrics.slice('P/E', 'Forward P/E', 'PEG', 'P/S', 'P/FCF', 'Profit Margin', 'ROE', 'ROIC', 'Debt/Eq', 'Sales Y/Y TTM', 'Sales Q/Q', 'EV/EBITDA')} eps_next_y=#{eps_next_y_dollar} eps_next_y_pct=#{eps_next_y_pct}")

      sector_link   = doc.at_css("a[href*='f=sec_']")
      industry_link = doc.at_css("a[href*='f=ind_']")

      FundamentalsData.new(
        pe:           decimal(metrics["P/E"]),
        fwd_pe:       decimal(metrics["Forward P/E"]),
        peg:          decimal(metrics["PEG"]),
        ps:           decimal(metrics["P/S"]),
        pfcf:         decimal(metrics["P/FCF"]),
        net_margin:   pct(metrics["Profit Margin"]),
        roe:          pct(metrics["ROE"]),
        roic:         pct(metrics["ROIC"]),
        debt_eq:      decimal(metrics["Debt/Eq"]),
        sales_5y:     pct(metrics["Sales Y/Y TTM"]),
        sales_qq:     pct(metrics["Sales Q/Q"]),
        ev_ebitda:    decimal(metrics["EV/EBITDA"]),
        sector:       sector_link&.text&.strip.presence,
        industry:     industry_link&.text&.strip.presence,
        eps_next_y:   decimal(eps_next_y_dollar),
        eps_next_y_pct: pct(eps_next_y_pct)
      )
    end

    def decimal(val)
      return nil if val.nil? || val.strip.in?([ "-", "", "N/A" ])
      BigDecimal(val.to_s.gsub(",", ""))
    rescue ArgumentError, TypeError
      nil
    end

    def pct(val)
      return nil if val.nil? || val.strip.in?([ "-", "", "N/A" ])
      BigDecimal(val.to_s.delete("%,").strip)
    rescue ArgumentError, TypeError
      nil
    end
  end
end
