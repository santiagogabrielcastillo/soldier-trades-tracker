# frozen_string_literal: true

class SpotController < ApplicationController
  MAX_CSV_SIZE = 10.megabytes

  def index
    @spot_account = SpotAccount.find_or_create_default_for(current_user)
    @view = (params[:view].to_s == "transactions") ? "transactions" : "portfolio"

    if @view == "transactions"
      relation = load_spot_transactions_filtered
      @pagy, @transactions = pagy(:offset, relation, limit: 25)
      @from_date = params[:from_date].presence
      @to_date = params[:to_date].presence
      @filter_token = params[:token].presence
      @filter_side = params[:side].presence if params[:side].to_s.in?(%w[buy sell deposit withdraw])
      @tokens_for_filter = @spot_account.spot_transactions.distinct.pluck(:token).sort
    else
      load_index_data
    end
  end

  def import
    @spot_account = current_user.spot_accounts.find_by(id: params[:spot_account_id])
    @spot_account ||= SpotAccount.find_or_create_default_for(current_user)

    unless params[:csv_file].present?
      redirect_to spot_path, alert: "Please select a CSV file." and return
    end

    file = params[:csv_file]
    if file.respond_to?(:size) && file.size > MAX_CSV_SIZE
      redirect_to spot_path, alert: "CSV file must be under #{MAX_CSV_SIZE / 1.megabyte} MB." and return
    end

    result = Spot::ImportFromCsvService.call(spot_account: @spot_account, csv_io: file)
    notice = "Imported #{result.created} row(s), #{result.skipped} skipped (duplicates)."
    notice += " Errors: #{result.errors.join('; ')}" if result.errors.any?
    redirect_to spot_path, notice: notice
  rescue ArgumentError => e
    redirect_to spot_path, alert: e.message
  end

  def create
    @spot_account = SpotAccount.find_or_create_default_for(current_user)
    permitted = spot_transaction_params
    side = permitted[:side].to_s.strip.downcase.presence
    side = nil unless side&.in?(%w[buy sell deposit withdraw])
    executed_at = parse_executed_at(permitted[:executed_at])
    amount = parse_decimal_param(permitted[:amount])

    if side.in?(%w[deposit withdraw]) && executed_at && amount && amount.positive?
      tx = build_cash_transaction(permitted, side, executed_at, amount)
      if tx.save
        respond_to do |format|
          format.html { redirect_to spot_path, notice: "Cash movement added." }
          format.json { head :created, location: spot_path }
        end
        return
      end
      @spot_transaction = tx
    elsif side.in?(%w[buy sell])
      token = permitted[:token].to_s.strip.upcase.presence
      price_usd = parse_decimal_param(permitted[:price_usd])
      if token && executed_at && price_usd && amount && amount.positive?
        total_value_usd = amount * price_usd
        row_signature = Spot::CsvRowParser.row_signature(executed_at, token, side, price_usd, amount)
        tx = @spot_account.spot_transactions.build(
          token: token,
          side: side,
          executed_at: executed_at,
          price_usd: price_usd,
          amount: amount,
          total_value_usd: total_value_usd,
          row_signature: row_signature
        )
        if tx.save
          respond_to do |format|
            format.html { redirect_to spot_path, notice: "Transaction added." }
            format.json { head :created, location: spot_path }
          end
          return
        end
        if tx.errors[:row_signature].any?
          respond_to do |format|
            format.html { redirect_to spot_path, alert: "This transaction already exists." }
            format.json { render json: { error: "This transaction already exists." }, status: :unprocessable_entity }
          end
          return
        end
        @spot_transaction = tx
      else
        @spot_transaction = build_invalid_spot_transaction(permitted)
      end
    else
      @spot_transaction = build_invalid_spot_transaction(permitted)
    end

    respond_to do |format|
      format.html do
        @view = "portfolio"
        load_index_data
        @open_new_transaction_modal = true
        render :index, status: :unprocessable_entity
      end
      format.json { render json: { errors: @spot_transaction.errors.to_hash }, status: :unprocessable_entity }
    end
  end

  def sync_prices
    @spot_account = SpotAccount.find_or_create_default_for(current_user)
    all_positions = Spot::PositionStateService.call(spot_account: @spot_account)
    open_tokens = all_positions.select(&:open?).map(&:token).uniq
    prices = Spot::CurrentPriceFetcher.call(tokens: open_tokens)
    @spot_account.cache_prices!(prices)
    redirect_to spot_path, notice: "Prices updated."
  end

  def edit
    @spot_account = SpotAccount.find_or_create_default_for(current_user)
    @transaction = @spot_account.spot_transactions.find(params[:id])
    render partial: "edit_form", locals: { transaction: @transaction }
  rescue ActiveRecord::RecordNotFound
    render plain: "Not found", status: :not_found
  end

  def update
    @spot_account = SpotAccount.find_or_create_default_for(current_user)
    @transaction = @spot_account.spot_transactions.find(params[:id])

    permitted = spot_transaction_params
    executed_at = parse_executed_at(permitted[:executed_at])
    amount = parse_decimal_param(permitted[:amount])

    attrs = build_update_attrs(@transaction, permitted, executed_at, amount)

    if attrs && @transaction.update(attrs)
      redirect_to spot_path(view: "transactions"), notice: "Transaction updated."
    else
      @transaction.errors.add(:base, "Invalid parameters.") if attrs.nil?
      render partial: "edit_form", locals: { transaction: @transaction }, status: :unprocessable_entity
    end
  rescue ActiveRecord::RecordNotFound
    render plain: "Not found", status: :not_found
  end

  def destroy
    @spot_account = SpotAccount.find_or_create_default_for(current_user)
    @transaction = @spot_account.spot_transactions.find(params[:id])
    @transaction.destroy!
    redirect_to spot_path(view: "transactions"), notice: "Transaction deleted."
  rescue ActiveRecord::RecordNotFound
    render plain: "Not found", status: :not_found
  end

  def confirm_destroy
    @spot_account = SpotAccount.find_or_create_default_for(current_user)
    @transaction = @spot_account.spot_transactions.find(params[:id])
    render partial: "delete_confirm", locals: { transaction: @transaction }
  rescue ActiveRecord::RecordNotFound
    render plain: "Not found", status: :not_found
  end

  private

  def parse_executed_at(value)
    return nil if value.blank?
    Time.zone.parse(value.to_s)
  end

  def parse_decimal_param(value)
    return nil if value.blank?
    BigDecimal(value.to_s.gsub(",", ""))
  rescue ArgumentError, TypeError
    nil
  end

  def build_cash_transaction(permitted, side, executed_at, amount)
    price_usd = BigDecimal("1")
    total_value_usd = amount
    row_signature = "cash|#{executed_at.to_i}|#{SecureRandom.hex(8)}"
    @spot_account.spot_transactions.build(
      token: "USDT",
      side: side,
      executed_at: executed_at,
      price_usd: price_usd,
      amount: amount,
      total_value_usd: total_value_usd,
      row_signature: row_signature
    )
  end

  def build_invalid_spot_transaction(req_params)
    amt = parse_decimal_param(req_params[:amount])
    pr = parse_decimal_param(req_params[:price_usd])
    side = req_params[:side].to_s.strip.downcase.presence
    token = req_params[:token].to_s.strip.upcase.presence
    price_usd = side.in?(%w[deposit withdraw]) ? BigDecimal("1") : pr
    total_value_usd = side.in?(%w[deposit withdraw]) ? amt : (amt && pr ? amt * pr : nil)
    # Temporary signature so validations run; this record is never persisted.
    SpotTransaction.new(
      spot_account: @spot_account,
      token: side.in?(%w[deposit withdraw]) ? "USDT" : token,
      side: side,
      executed_at: parse_executed_at(req_params[:executed_at]),
      price_usd: price_usd,
      amount: amt,
      total_value_usd: total_value_usd,
      row_signature: SecureRandom.hex(32)
    ).tap(&:validate)
  end

  def load_spot_transactions_filtered
    relation = @spot_account.spot_transactions.newest_first
    relation = relation.where("executed_at >= ?", params[:from_date].to_date.beginning_of_day) if params[:from_date].present?
    relation = relation.where("executed_at <= ?", params[:to_date].to_date.end_of_day) if params[:to_date].present?
    relation = relation.where(token: params[:token]) if params[:token].present?
    relation = relation.where(side: params[:side]) if params[:side].to_s.in?(%w[buy sell deposit withdraw])
    relation
  rescue ArgumentError, TypeError
    # Invalid date params: ignore filter
    @spot_account.spot_transactions.newest_first
  end

  def load_index_data
    all_positions = Spot::PositionStateService.call(spot_account: @spot_account)
    open_positions = all_positions.select(&:open?)
    @current_prices = @spot_account.prices_as_decimals
    @prices_synced_at = @spot_account.prices_synced_at
    @positions = open_positions.sort_by { |pos| -((@current_prices[pos.token] || 0).to_d * pos.balance) }
    @tokens_for_select = tokens_for_select_for(@spot_account)
    @cash_balance = @spot_account.cash_balance
    @spot_value = open_positions.sum(BigDecimal("0")) { |pos| (@current_prices[pos.token] || 0).to_d * pos.balance }
    @total_portfolio = @spot_value + @cash_balance
    @cash_pct = @total_portfolio.positive? ? (@cash_balance / @total_portfolio * 100).round(2) : nil
    @spot_pie_data = @spot_value.positive? ? @positions.filter_map { |pos|
      val = (@current_prices[pos.token] || 0).to_d * pos.balance
      next if val.zero?
      { token: pos.token, pct: (val / @spot_value * 100).round(2) }
    } : []
    @scenario_positions_json = @positions.map do |pos|
      {
        token: pos.token,
        balance: pos.balance.to_s,
        net_usd_invested: pos.net_usd_invested.to_s,
        breakeven: pos.breakeven.to_s,
        current_price: @current_prices[pos.token]&.to_s
      }
    end.to_json
  end

  def spot_transaction_params
    if params[:spot_transaction].present?
      params.require(:spot_transaction).permit(:token, :side, :amount, :price_usd, :executed_at)
    else
      params.permit(:token, :side, :amount, :price_usd, :executed_at)
    end
  end

  def build_update_attrs(transaction, permitted, executed_at, amount)
    return nil unless executed_at && amount && amount.positive?

    if transaction.side.in?(%w[deposit withdraw])
      total_value_usd = amount
      row_signature = "cash|#{executed_at.to_i}|#{transaction.id}"
      { amount: amount, executed_at: executed_at, total_value_usd: total_value_usd, row_signature: row_signature }
    else
      token = permitted[:token].to_s.strip.upcase.presence
      price_usd = parse_decimal_param(permitted[:price_usd])
      return nil unless token && price_usd && price_usd >= 0

      total_value_usd = amount * price_usd
      row_signature = Spot::CsvRowParser.row_signature(executed_at, token, transaction.side, price_usd, amount)
      { token: token, price_usd: price_usd, amount: amount, executed_at: executed_at, total_value_usd: total_value_usd, row_signature: row_signature }
    end
  end

  def tokens_for_select_for(spot_account)
    (spot_account.spot_transactions.distinct.pluck(:token) + Spot::TokenList::LIST).uniq.sort
  end
end
