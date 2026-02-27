# frozen_string_literal: true

module Exchanges
  # Abstract base for exchange API clients. Subclasses must implement #fetch_my_trades.
  class BaseProvider
    # Returns an array of normalized trade hashes for the unified Trade model.
    #
    # Two styles of hash are supported (sync job handles both):
    # - Trade-style: exchange_reference_id, symbol, side, price, quantity, fee_from_exchange, executed_at, raw_payload.
    #   Fee and net_amount are computed by Exchanges::FinancialCalculator in the job.
    # - Income-style: exchange_reference_id, symbol, side, fee, net_amount, executed_at, raw_payload.
    #   No price/quantity; fee and net_amount come from the exchange.
    #
    # @param since [Time] only return trades with executed_at >= since (Day 0)
    # @return [Array<Hash>]
    def fetch_my_trades(since:)
      raise NotImplementedError, "#{self.class} must implement #fetch_my_trades(since:)"
    end
  end
end
