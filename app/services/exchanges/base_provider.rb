# frozen_string_literal: true

module Exchanges
  # Abstract base for exchange API clients. Subclasses must implement #fetch_my_trades.
  class BaseProvider
    # Returns an array of normalized trade hashes for the unified Trade model.
    # Each hash must have: exchange_reference_id, symbol, side, fee, net_amount, executed_at, raw_payload.
    #
    # @param since [Time] only return trades with executed_at >= since (Day 0)
    # @return [Array<Hash>]
    def fetch_my_trades(since:)
      raise NotImplementedError, "#{self.class} must implement #fetch_my_trades(since:)"
    end
  end
end
