# frozen_string_literal: true

namespace :positions do
  desc "Delete duplicate positions (same account, symbol, position_side, open_at, close_at, open); keeps oldest by id"
  task deduplicate: :environment do
    duplicate_groups = Position
      .group(:exchange_account_id, :symbol, :position_side, :open_at, :close_at, :open)
      .having("COUNT(*) > 1")
      .pluck(:exchange_account_id, :symbol, :position_side, :open_at, :close_at, :open)

    deleted = 0
    duplicate_groups.each do |exchange_account_id, symbol, position_side, open_at, close_at, open_flag|
      kept = Position.where(
        exchange_account_id: exchange_account_id,
        symbol: symbol,
        position_side: position_side,
        open_at: open_at,
        close_at: close_at,
        open: open_flag
      ).order(:id).first!
      Position.where(
        exchange_account_id: exchange_account_id,
        symbol: symbol,
        position_side: position_side,
        open_at: open_at,
        close_at: close_at,
        open: open_flag
      ).where.not(id: kept.id).find_each do |position|
        position.destroy
        deleted += 1
      end
    end

    puts "Deleted #{deleted} duplicate position(s) across #{duplicate_groups.size} duplicate group(s)."
  end

  desc "Backfill Position and PositionTrade rows from existing Trade data (one-time after Phase 2 deploy)"
  task backfill: :environment do
    count = 0
    ExchangeAccount.find_each do |account|
      Positions::RebuildForAccountService.call(account)
      count += 1
      print "." if (count % 10).zero?
    end
    puts "\nBackfilled positions for #{count} exchange account(s)."
  end
end
