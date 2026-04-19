# frozen_string_literal: true

require "net/http"

module Exchanges
  module Binance
    # Fetches current USD prices for spot tokens via the CoinGecko API.
    # Uses GET /api/v3/simple/price?ids=...&vs_currencies=usd — one batched request for all tokens.
    # CoinGecko is used instead of Binance because Binance (fapi.binance.com) is geo-blocked from
    # some cloud providers such as Railway/AWS.
    #
    # When ENV['COINGECKO_API_KEY'] is set, the x-cg-demo-api-key header is included (demo tier).
    #
    # Symbol → CoinGecko ID mapping: common tokens are listed in SYMBOL_TO_ID; unknown tokens fall
    # back to the lowercase symbol (works for many tokens whose CoinGecko ID matches their ticker,
    # e.g. "aave" → "aave"). The reverse mapping (id → token symbol) is used when building the
    # result hash so callers always receive the original token symbol as the key.
    class SpotTickerFetcher
      BASE_URL = "https://api.coingecko.com"
      SIMPLE_PRICE_PATH = "/api/v3/simple/price"
      OPEN_TIMEOUT = 5
      READ_TIMEOUT = 15

      # Mapping from uppercase token symbol to CoinGecko coin ID.
      # Add entries here whenever a symbol's CoinGecko ID differs from its lowercase ticker.
      SYMBOL_TO_ID = {
        "BTC"   => "bitcoin",
        "ETH"   => "ethereum",
        "SOL"   => "solana",
        "BNB"   => "binancecoin",
        "XRP"   => "ripple",
        "ADA"   => "cardano",
        "DOT"   => "polkadot",
        "DOGE"  => "dogecoin",
        "SHIB"  => "shiba-inu",
        "LTC"   => "litecoin",
        "AVAX"  => "avalanche-2",
        "LINK"  => "chainlink",
        "ATOM"  => "cosmos",
        "UNI"   => "uniswap",
        "MATIC" => "matic-network",
        "POL"   => "matic-network",
        "FTM"   => "fantom",
        "NEAR"  => "near",
        "ALGO"  => "algorand",
        "ETC"   => "ethereum-classic",
        "TRX"   => "tron",
        "XLM"   => "stellar",
        "VET"   => "vechain",
        "FIL"   => "filecoin",
        "HBAR"  => "hedera-hashgraph",
        "SAND"  => "the-sandbox",
        "MANA"  => "decentraland",
        "AXS"   => "axie-infinity",
        "LUNA"  => "terra-luna-2",
        "APE"   => "apecoin",
        "OP"    => "optimism",
        "ARB"   => "arbitrum",
        "SUI"   => "sui",
        "INJ"   => "injective-protocol",
        "MKR"   => "maker",
        "COMP"  => "compound-governance-token",
        "SNX"   => "havven",
        "CRV"   => "curve-dao-token",
        "LDO"   => "lido-dao",
        "GRT"   => "the-graph",
        "SUSHI" => "sushi",
        "YFI"   => "yearn-finance",
        "1INCH" => "1inch",
        "GMX"   => "gmx",
        "WLD"   => "worldcoin-wld",
        "ARK"   => "ark",
        "TIA"   => "celestia",
        "SEI"   => "sei-network",
        "JUP"   => "jupiter-exchange-solana",
        "PYTH"  => "pyth-network",
        "W"     => "wormhole",
        "ENA"   => "ethena",
        "EIGEN" => "eigenlayer",
        "PENDLE"=> "pendle",
        "STRK"  => "starknet",
        "BLUR"  => "blur",
        "DYDX"  => "dydx-chain",
        "ONDO"  => "ondo-finance",
      }.freeze

      # @param tokens [Array<String>] list of token symbols (e.g. ["AAVE", "BTC"])
      # @param api_key [String, nil] optional CoinGecko demo API key (user-supplied BYOK)
      # @return [Hash<String, BigDecimal>] token => price; only includes tokens that succeeded
      def self.fetch_prices(tokens:, api_key: nil)
        new(api_key: api_key).fetch_prices(tokens: tokens)
      end

      def initialize(api_key: nil)
        @api_key = api_key
      end

      def fetch_prices(tokens:)
        return {} if tokens.blank?
        tokens = tokens.uniq.map { |t| t.to_s.strip.upcase }.reject(&:blank?)
        return {} if tokens.empty?

        id_to_token = tokens.each_with_object({}) do |token, h|
          id = SYMBOL_TO_ID[token] || token.downcase
          h[id] = token
        end

        ids = id_to_token.keys.join(",")
        uri = URI("#{BASE_URL}#{SIMPLE_PRICE_PATH}")
        uri.query = URI.encode_www_form("ids" => ids, "vs_currencies" => "usd", "precision" => "8")

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.open_timeout = OPEN_TIMEOUT
        http.read_timeout = READ_TIMEOUT
        req = Net::HTTP::Get.new(uri)
        req["Accept"] = "application/json"
        req["x-cg-demo-api-key"] = @api_key if @api_key.present?

        res = http.request(req)
        unless res.code.to_s == "200"
          Rails.logger.warn("[Binance::SpotTickerFetcher] CoinGecko HTTP #{res.code}: #{res.body.to_s[0..200]}")
          return {}
        end

        data = JSON.parse(res.body)
        result = {}
        data.each do |id, prices|
          token = id_to_token[id]
          next unless token
          price = prices["usd"].to_s.strip
          next if price.blank?
          parsed = price.to_d
          result[token] = parsed if parsed.positive?
        end
        result
      rescue Net::OpenTimeout, Net::ReadTimeout, Timeout::Error => e
        Rails.logger.warn("[Binance::SpotTickerFetcher] Timeout: #{e.message}")
        {}
      rescue JSON::ParserError => e
        Rails.logger.warn("[Binance::SpotTickerFetcher] Parse error: #{e.message}")
        {}
      rescue StandardError => e
        Rails.logger.warn("[Binance::SpotTickerFetcher] Error: #{e.class} #{e.message}")
        {}
      end
    end
  end
end
