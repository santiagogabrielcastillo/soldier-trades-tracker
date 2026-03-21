# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

module Stocks
  # Fetches the MEP (Dolar Bolsa) exchange rate in ARS per USD.
  # Tries two free sources in order; returns BigDecimal or nil on total failure.
  #
  # Primary:  dolarapi.com/v1/cotizaciones/bolsa         → { "venta": 1234.5 }
  # Fallback: argentinadatos.com/v1/cotizaciones/dolares/bolsa → { "venta": 1234.5 }
  class MepRateFetcher
    SOURCES = [
      { url: "https://dolarapi.com/v1/cotizaciones/bolsa",                              key: "venta" },
      { url: "https://api.argentinadatos.com/v1/cotizaciones/dolares/bolsa",            key: "venta" }
    ].freeze

    def self.call
      Rails.cache.fetch("mep_rate", expires_in: 15.minutes, skip_nil: true) do
        fetch_first_available
      end
    end

    def self.fetch_first_available
      SOURCES.each do |source|
        rate = fetch_from(source[:url], source[:key])
        return rate if rate
      end
      nil
    end
    private_class_method :fetch_first_available

    def self.fetch_from(url, key)
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

    private_class_method :fetch_from
  end
end
