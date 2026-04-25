class Admin::AuditLogController < Admin::BaseController
  STUDENT_ITEM_TYPES = %w[
    Trade SpotTransaction StockTrade Portfolio
    ExchangeAccount SpotAccount StockPortfolio
    AllocationBucket AllocationManualEntry
  ].freeze

  def show
    versions = PaperTrail::Version.where(item_type: STUDENT_ITEM_TYPES)
                                  .order(created_at: :desc)

    if params[:student_id].present?
      @selected_student = User.find_by(id: params[:student_id])
      versions = filter_versions_for_student(versions, @selected_student) if @selected_student
    end

    versions = versions.where(event: params[:event]) if params[:event].present?
    versions = versions.where("created_at >= ?", Date.parse(params[:from_date])) if params[:from_date].present?
    versions = versions.where("created_at <= ?", Date.parse(params[:to_date]).end_of_day) if params[:to_date].present?

    @pagy, @versions = pagy(:offset, versions, limit: 50)
    @students = User.where(role: "user").order(:email)
  end

  private

  def filter_versions_for_student(versions, student)
    trade_ids         = Trade.unscoped.where(exchange_account: student.exchange_accounts).select(:id)
    spot_tx_ids       = SpotTransaction.unscoped.where(spot_account: student.spot_accounts).select(:id)
    stock_trade_ids   = StockTrade.unscoped.where(stock_portfolio: student.stock_portfolios).select(:id)
    portfolio_ids     = Portfolio.unscoped.where(user: student).select(:id)
    exchange_acct_ids = student.exchange_accounts.select(:id)
    spot_acct_ids     = student.spot_accounts.select(:id)
    stock_port_ids    = student.stock_portfolios.select(:id)
    alloc_bucket_ids  = AllocationBucket.unscoped.where(user: student).select(:id)
    alloc_entry_ids   = AllocationManualEntry.unscoped.where(user: student).select(:id)

    versions.where(
      "(item_type = 'Trade'                  AND item_id IN (?)) OR
       (item_type = 'SpotTransaction'        AND item_id IN (?)) OR
       (item_type = 'StockTrade'             AND item_id IN (?)) OR
       (item_type = 'Portfolio'              AND item_id IN (?)) OR
       (item_type = 'ExchangeAccount'        AND item_id IN (?)) OR
       (item_type = 'SpotAccount'            AND item_id IN (?)) OR
       (item_type = 'StockPortfolio'         AND item_id IN (?)) OR
       (item_type = 'AllocationBucket'       AND item_id IN (?)) OR
       (item_type = 'AllocationManualEntry'  AND item_id IN (?))",
      trade_ids, spot_tx_ids, stock_trade_ids, portfolio_ids,
      exchange_acct_ids, spot_acct_ids, stock_port_ids,
      alloc_bucket_ids, alloc_entry_ids
    )
  end
end
