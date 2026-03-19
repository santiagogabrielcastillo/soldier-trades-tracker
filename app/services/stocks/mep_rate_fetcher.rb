# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

module Stocks
  # Fetches the MEP (Dolar Bolsa) exchange rate in ARS per USD from dolarapi.com.
  # Free, no authentication required.
  # Returns BigDecimal or nil on any failure.
  class MepRateFetcher
    URL = "https://dolarapi.com/v1/cotizaciones/bolsa"

    def self.call
      response = Net::HTTP.get_response(URI(URL))
      return nil unless response.is_a?(Net::HTTPSuccess)

      data = JSON.parse(response.body)
      venta = data["venta"]
      return nil if venta.blank? || venta.to_d.zero?

      venta.to_d
    rescue => e
      Rails.logger.error("[Stocks::MepRateFetcher] Error: #{e.message}")
      nil
    end
  end
end
