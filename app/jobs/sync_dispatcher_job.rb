# frozen_string_literal: true

# Runs on a schedule (e.g. every 15 min). Enqueues SyncExchangeAccountJob for users
# who are due for a sync based on their sync_interval and last run time.
# Rate limit (2 runs/day per account) is enforced by ExchangeAccount#can_sync?.
class SyncDispatcherJob < ApplicationJob
  queue_as :default

  def perform
    now = Time.current.utc

    User.where.not(sync_interval: nil).find_each do |user|
      next unless user_due?(user, now)

      user.exchange_accounts.find_each do |account|
        next unless Exchanges::ProviderForAccount.new(account).supported?
        next unless account.can_sync?

        SyncExchangeAccountJob.perform_later(account.id)
      end
    end
  end

  private

  def user_due?(user, now)
    interval = user.sync_interval
    return false if interval.blank?

    last_run = user.exchange_accounts.maximum(:last_synced_at)&.utc

    case interval
    when "hourly"
      last_run.nil? || last_run <= now - 1.hour
    when "daily"
      last_run.nil? || last_run <= now - 1.day
    when "twice_daily"
      return false unless [ 8, 20 ].include?(now.hour)
      # Run at 08:00 and 20:00 UTC; due if we haven't run in this slot today
      slot_start = now.beginning_of_day + (now.hour == 8 ? 8.hours : 20.hours)
      last_run.nil? || last_run < slot_start
    else
      false
    end
  end
end
