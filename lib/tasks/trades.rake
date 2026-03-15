# frozen_string_literal: true

namespace :trades do
  desc "Delete duplicate trades (same account, symbol, executed_at, side, net_amount); keeps oldest by id"
  task deduplicate: :environment do
    duplicate_groups = Trade
      .group(:exchange_account_id, :symbol, :executed_at, :side, :net_amount)
      .having("COUNT(*) > 1")
      .pluck(:exchange_account_id, :symbol, :executed_at, :side, :net_amount)

    deleted = 0
    duplicate_groups.each do |exchange_account_id, symbol, executed_at, side, net_amount|
      kept = Trade.where(
        exchange_account_id: exchange_account_id,
        symbol: symbol,
        executed_at: executed_at,
        side: side,
        net_amount: net_amount
      ).order(:id).first!
      Trade.where(
        exchange_account_id: exchange_account_id,
        symbol: symbol,
        executed_at: executed_at,
        side: side,
        net_amount: net_amount
      ).where.not(id: kept.id).find_each do |trade|
        trade.destroy
        deleted += 1
      end
    end

    puts "Deleted #{deleted} duplicate trade(s) across #{duplicate_groups.size} duplicate group(s)."
  end
end
