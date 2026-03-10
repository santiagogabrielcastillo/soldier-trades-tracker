# frozen_string_literal: true

namespace :positions do
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
