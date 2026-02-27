# frozen_string_literal: true

require "net/http"
require "openssl"

module Exchanges
  module Bingx
    # Signed GET for BingX API. Builds URI, signs with HMAC-SHA256, sends request,
    # parses JSON. Raises Exchanges::ApiError for 429, 5xx, timeouts, empty body, parse errors.
    class HttpClient
      def initialize(api_key:, api_secret:, base_url: "https://open-api.bingx.com")
        @api_key = api_key
        @api_secret = api_secret
        @base_url = base_url
      end

      def get(path, params = {})
        if @api_secret.blank?
          raise ArgumentError, "BingX API secret is missing. Ensure the exchange account credentials are set and encryption is available in this process."
        end

        timestamp = (Time.now.to_f * 1000).to_i
        params = params.merge("timestamp" => timestamp)
        query = params.sort.map { |k, v| "#{k}=#{v}" }.join("&")
        signature = OpenSSL::HMAC.hexdigest("SHA256", @api_secret, query)

        uri = URI("#{@base_url}#{path}")
        uri.query = "#{query}&signature=#{signature}"

        req = Net::HTTP::Get.new(uri)
        req["X-BX-APIKEY"] = @api_key

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.open_timeout = 10
        http.read_timeout = 15
        res = http.request(req)

        code = res.code.to_s
        if code != "200"
          parsed = (JSON.parse(res.body) if res.body.presence) rescue nil
          msg = parsed&.dig("msg") || res.body.to_s[0..500]
          if code == "429" || code.start_with?("5")
            retry_after = res["Retry-After"]&.to_i
            raise ApiError.new("BingX API error #{code}: #{msg}", response_code: code, retry_after: retry_after)
          end
          raise "BingX API error #{code}: #{msg}"
        end

        if res.body.blank?
          raise ApiError, "BingX API returned empty body (status 200)"
        end

        begin
          JSON.parse(res.body)
        rescue JSON::ParserError => e
          snippet = res.body.to_s[0..200].gsub(/\s+/, " ")
          raise ApiError, "BingX API non-JSON response: #{snippet}. #{e.message}"
        end
      rescue Net::OpenTimeout, Net::ReadTimeout, Timeout::Error => e
        raise ApiError, "BingX API timeout: #{e.message}"
      end
    end
  end
end
