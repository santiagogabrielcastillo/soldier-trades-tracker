# frozen_string_literal: true

module Ai
  class PortfolioContextBuilder
    CLOSED_POSITIONS_LIMIT = 50

    def initialize(user:)
      @user = user
    end

    def call
      sections = []
      sections << "Portfolio context as of #{Date.today.strftime('%B %d, %Y')}:"
      sections << futures_section
      sections << spot_section
      sections << stocks_section
      sections << allocation_section
      sections << watchlist_section
      sections.join("\n\n")
    end

    private

    def futures_section
      all_positions = Position.for_user(@user).ordered_for_display.to_a
      open_positions = all_positions.select(&:open?)
      closed_positions = all_positions.reject(&:open?).first(CLOSED_POSITIONS_LIMIT)
      positions = open_positions + closed_positions

      lines = ["## Crypto Futures Positions"]
      if positions.empty?
        lines << "No futures positions found."
        return lines.join("\n")
      end

      lines << "| Symbol | Side | Status | Entry Price | Net P&L | ROI% | Leverage |"
      lines << "|--------|------|--------|-------------|---------|------|----------|"
      positions.each do |p|
        status = p.open? ? "Open" : "Closed"
        entry = p.entry_price ? "$#{p.entry_price.round(4)}" : "—"
        pl = p.net_pl ? "$#{p.net_pl.round(2)}" : "—"
        roi = p.roi_percent ? "#{p.roi_percent}%" : "—"
        lev = p.leverage ? "#{p.leverage}x" : "—"
        lines << "| #{p.symbol} | #{p.position_side} | #{status} | #{entry} | #{pl} | #{roi} | #{lev} |"
      end
      lines.join("\n")
    end

    def spot_section
      spot_account = SpotAccount.find_or_create_default_for(@user)
      positions = Spot::PositionStateService.call(spot_account: spot_account)
      open_positions = positions.select(&:open?)

      lines = ["## Spot Holdings"]
      if open_positions.empty?
        lines << "No spot positions found."
        return lines.join("\n")
      end

      lines << "| Token | Balance | Net USD Invested | Breakeven |"
      lines << "|-------|---------|-----------------|-----------|"
      open_positions.each do |p|
        bal = p.balance ? p.balance.round(6) : "—"
        invested = p.net_usd_invested ? "$#{p.net_usd_invested.round(2)}" : "—"
        be = p.breakeven ? "$#{p.breakeven.round(4)}" : "—"
        lines << "| #{p.token} | #{bal} | #{invested} | #{be} |"
      end
      lines.join("\n")
    end

    def stocks_section
      stock_portfolio = StockPortfolio.find_or_create_default_for(@user)
      positions = Stocks::PositionStateService.call(stock_portfolio: stock_portfolio)
      open_positions = positions.select(&:open?)

      lines = ["## Stock Portfolio"]
      if open_positions.empty?
        lines << "No stock positions found."
        return lines.join("\n")
      end

      lines << "| Ticker | Shares | Net USD Invested | Breakeven |"
      lines << "|--------|--------|-----------------|-----------|"
      open_positions.each do |p|
        shares = p.shares ? p.shares.round(4) : "—"
        invested = p.net_usd_invested ? "$#{p.net_usd_invested.round(2)}" : "—"
        be = p.breakeven ? "$#{p.breakeven.round(4)}" : "—"
        lines << "| #{p.ticker} | #{shares} | #{invested} | #{be} |"
      end
      lines.join("\n")
    end

    def allocation_section
      summary = Allocations::SummaryService.call(user: @user)
      lines = ["## Asset Allocation"]

      if summary.buckets.empty?
        lines << "No allocation buckets configured."
        return lines.join("\n")
      end

      lines << "| Bucket | Target % | Actual % | Drift % |"
      lines << "|--------|----------|----------|---------|"
      summary.buckets.each do |b|
        target = b.target_pct ? "#{b.target_pct}%" : "—"
        actual = b.actual_pct ? "#{b.actual_pct}%" : "—"
        drift  = b.drift_pct  ? "#{b.drift_pct > 0 ? '+' : ''}#{b.drift_pct}%" : "—"
        lines << "| #{b.name} | #{target} | #{actual} | #{drift} |"
      end
      lines.join("\n")
    end

    def watchlist_section
      tickers = @user.watchlist_tickers.ordered.map(&:ticker)
      lines = ["## Watchlist"]

      if tickers.empty?
        lines << "No watchlist tickers."
        return lines.join("\n")
      end

      fundamentals = StockFundamental.for_tickers(tickers)

      lines << "| Ticker | P/E | Fwd P/E | PEG | Net Margin% | ROE% |"
      lines << "|--------|-----|---------|-----|-------------|------|"
      tickers.each do |ticker|
        f = fundamentals[ticker]
        pe      = f&.pe      ? f.pe.round(1)      : "—"
        fwd_pe  = f&.fwd_pe  ? f.fwd_pe.round(1)  : "—"
        peg     = f&.peg     ? f.peg.round(2)     : "—"
        margin  = f&.net_margin ? "#{f.net_margin.round(1)}%" : "—"
        roe     = f&.roe     ? "#{f.roe.round(1)}%" : "—"
        lines << "| #{ticker} | #{pe} | #{fwd_pe} | #{peg} | #{margin} | #{roe} |"
      end
      lines.join("\n")
    end
  end
end
