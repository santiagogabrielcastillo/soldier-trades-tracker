# frozen_string_literal: true

module Allocations
  class SummaryService
    BucketData = Struct.new(
      :id, :name, :color, :target_pct,
      :actual_usd, :actual_pct, :drift_pct, :sources,
      keyword_init: true
    )

    SourceData = Struct.new(:label, :amount_usd, :source_type, keyword_init: true)

    Result = Struct.new(:buckets, :total_usd, :unassigned_sources, keyword_init: true)

    def self.call(user:, mep_rate: nil)
      new(user: user, mep_rate: mep_rate).call
    end

    def initialize(user:, mep_rate: nil)
      @user = user
      @mep_rate = mep_rate
    end

    def call
      buckets = @user.allocation_buckets.ordered
      manual_by_bucket    = @user.allocation_manual_entries.group_by(&:allocation_bucket_id)
      portfolios_by_bucket = @user.stock_portfolios.where.not(allocation_bucket_id: nil)
                                   .group_by(&:allocation_bucket_id)
      spot_by_bucket      = @user.spot_accounts.where.not(allocation_bucket_id: nil)
                                   .group_by(&:allocation_bucket_id)

      bucket_data = buckets.map do |bucket|
        sources = []

        (manual_by_bucket[bucket.id] || []).each do |entry|
          sources << SourceData.new(label: entry.label, amount_usd: entry.amount_usd.to_d, source_type: :manual)
        end

        (portfolios_by_bucket[bucket.id] || []).each do |portfolio|
          usd = stock_portfolio_usd(portfolio)
          sources << SourceData.new(label: portfolio.name, amount_usd: usd, source_type: :stock_portfolio) if usd
        end

        (spot_by_bucket[bucket.id] || []).each do |spot|
          sources << SourceData.new(label: spot.name, amount_usd: spot_account_usd(spot), source_type: :spot_account)
        end

        BucketData.new(
          id: bucket.id, name: bucket.name, color: bucket.color,
          target_pct: bucket.target_pct&.to_d,
          actual_usd: sources.sum { |s| s.amount_usd },
          actual_pct: nil, drift_pct: nil, sources: sources
        )
      end

      total_usd = bucket_data.sum(&:actual_usd)

      bucket_data.each do |bd|
        bd.actual_pct = total_usd.positive? ? (bd.actual_usd / total_usd * 100).round(2) : BigDecimal("0")
        bd.drift_pct  = bd.target_pct ? (bd.actual_pct - bd.target_pct).round(2) : nil
      end

      unassigned = unassigned_sources
      Result.new(buckets: bucket_data, total_usd: total_usd, unassigned_sources: unassigned)
    end

    private

    def stock_portfolio_usd(portfolio)
      snapshot = portfolio.stock_portfolio_snapshots.order(recorded_at: :desc).first
      return nil unless snapshot

      value = snapshot.total_value.to_d
      if portfolio.market == "argentina"
        return nil unless @mep_rate&.positive?
        (value / @mep_rate).round(2)
      else
        value
      end
    end

    def spot_account_usd(spot)
      positions = Spot::PositionStateService.call(spot_account: spot)
      open_positions = positions.select(&:open?)
      crypto_value = if open_positions.any?
        tokens = open_positions.map(&:token).uniq
        prices = Spot::CurrentPriceFetcher.call(tokens: tokens)
        open_positions.sum(BigDecimal("0")) { |pos| (prices[pos.token] || 0).to_d * pos.balance }
      else
        BigDecimal("0")
      end
      crypto_value + spot.cash_balance.to_d
    end

    def unassigned_sources
      sources = []
      @user.stock_portfolios.where(allocation_bucket_id: nil).each do |p|
        usd = stock_portfolio_usd(p)
        sources << SourceData.new(label: "#{p.name} (stocks)", amount_usd: usd || BigDecimal("0"), source_type: :stock_portfolio)
      end
      @user.spot_accounts.where(allocation_bucket_id: nil).each do |s|
        sources << SourceData.new(label: "#{s.name} (spot)", amount_usd: spot_account_usd(s), source_type: :spot_account)
      end
      sources
    end
  end
end
