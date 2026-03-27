# frozen_string_literal: true

require "net/http"
require "uri"
require "json"
require "nokogiri"

module Stocks
  # Fetches the MEP (Dolar Bolsa) exchange rate in ARS per USD.
  # Tries sources in order; returns BigDecimal or nil on total failure.
  #
  # Primary:  dolarhoy.com scrape → average of compra/venta for Dólar MEP
  # Fallback: dolarapi.com/v1/cotizaciones/bolsa         → { "venta": 1234.5 }
  # Fallback: argentinadatos.com/v1/cotizaciones/dolares/bolsa → { "venta": 1234.5 }
  class MepRateFetcher
    JSON_SOURCES = [
      { url: "https://dolarapi.com/v1/cotizaciones/bolsa",                         key: "venta" },
      { url: "https://api.argentinadatos.com/v1/cotizaciones/dolares/bolsa",       key: "venta" }
    ].freeze

    def self.call
      Rails.cache.fetch("mep_rate", expires_in: 15.minutes, skip_nil: true) do
        fetch_first_available
      end
    end

    def self.fetch_first_available
      rate = fetch_from_dolarhoy
      return rate if rate

      JSON_SOURCES.each do |source|
        rate = fetch_from_json(source[:url], source[:key])
        return rate if rate
      end
      nil
    end
    private_class_method :fetch_first_available

    def self.fetch_from_dolarhoy
      response = Net::HTTP.get_response(URI("https://dolarhoy.com/"))
      return nil unless response.is_a?(Net::HTTPSuccess)

      doc = Nokogiri::HTML(response.body)
      mep_link = doc.at_css('a[href="/cotizaciondolarbolsa"]')
      return nil unless mep_link

      compra_text = mep_link.at_css(".compra")&.text&.strip
      venta_text  = mep_link.at_css(".venta")&.text&.strip
      return nil if compra_text.blank? || venta_text.blank?

      compra = compra_text.gsub(",", ".").to_d
      venta  = venta_text.gsub(",", ".").to_d
      return nil if compra.zero? || venta.zero?

      ((compra + venta) / 2).round(2)
    rescue => e
      Rails.logger.error("[Stocks::MepRateFetcher] dolarhoy.com error: #{e.message}")
      nil
    end
    private_class_method :fetch_from_dolarhoy

    def self.fetch_from_json(url, key)
      response = Net::HTTP.get_response(URI(url))
      return nil unless response.is_a?(Net::HTTPSuccess)

      data = JSON.parse(response.body)
      venta = data[key]
      return nil if venta.blank? || venta.to_d.zero?

      venta.to_d
    rescue => e
      Rails.logger.error("[Stocks::MepRateFetcher] #{url} error: #{e.message}")
      nil
    end
    private_class_method :fetch_from_json
  end
end
