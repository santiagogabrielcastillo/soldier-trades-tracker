# frozen_string_literal: true

# Shared logic for fetching Binance leverage by symbol and current prices for open positions.
# Used by Trades::IndexService and Dashboards::SummaryService to avoid duplication and extra API calls.
module Positions
  class CurrentDataFetcher
    LOG_PREFIX = "[Positions::CurrentDataFetcher]"

    # Binance userTrades does not return leverage; positionRisk does. Fetch once per Binance account and merge.
    # @param trades [Array<Trade>]
    # @return [Hash<String, Integer>] symbol => leverage
    def self.leverage_by_symbol(trades)
      accounts = trades.map(&:exchange_account).compact.uniq.select { |a| a.provider_type.to_s.downcase == "binance" }
      return {} if accounts.empty?

      merged = {}
      accounts.each do |account|
        client = Exchanges::ProviderForAccount.new(account).client
        next unless client.respond_to?(:leverage_by_symbol)

        leverage_by_symbol = client.leverage_by_symbol
        merged.merge!(leverage_by_symbol) if leverage_by_symbol.present?
      end
      merged
    rescue StandardError => e
      Rails.logger.warn("#{LOG_PREFIX} Binance leverage_by_symbol failed: #{e.message}")
      {}
    end

    # Fetches current ticker prices for open positions, grouped by provider. Skips positions with nil exchange_account and logs them.
    # @param positions [Array<PositionSummary>]
    # @return [Hash<String, BigDecimal>] symbol => price
    def self.current_prices_for_open_positions(positions)
      open_positions = positions.select(&:open?)
      return {} if open_positions.empty?

      with_account = open_positions.select { |p| p.exchange_account.present? }
      open_positions.reject { |p| p.exchange_account.present? }.each do |p|
        Rails.logger.warn("#{LOG_PREFIX} Skipping position with nil exchange_account: symbol=#{p.symbol}")
      end
      open_positions = with_account
      return {} if open_positions.empty?

      by_provider = open_positions.group_by { |p| p.exchange_account.provider_type.to_s.presence || "bingx" }
      result = {}
      by_provider.each do |provider_type, group|
        symbols = group.map(&:symbol).uniq
        next if symbols.empty?

        prices = case provider_type
        when "binance" then Exchanges::Binance::TickerFetcher.fetch_prices(symbols: symbols)
        else Exchanges::Bingx::TickerFetcher.fetch_prices(symbols: symbols)
        end
        result.merge!(prices)
      end
      result
    end
  end
end
