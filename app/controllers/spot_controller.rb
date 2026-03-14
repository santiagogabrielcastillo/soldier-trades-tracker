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
      @filter_side = params[:side].presence if params[:side].to_s.in?(%w[buy sell])
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
    token = permitted[:token].to_s.strip.upcase.presence
    side = permitted[:side].to_s.strip.downcase.presence
    side = nil unless side&.in?(%w[buy sell])
    executed_at = parse_executed_at(permitted[:executed_at])
    price_usd = parse_decimal_param(permitted[:price_usd])
    amount = parse_decimal_param(permitted[:amount])

    if token && side && executed_at && price_usd && amount
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
      # Other validation errors: re-render index with modal open (HTML) or return errors (JSON)
      @spot_transaction = tx
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

  def build_invalid_spot_transaction(req_params)
    amt = parse_decimal_param(req_params[:amount])
    pr = parse_decimal_param(req_params[:price_usd])
    # Temporary signature so validations run; this record is never persisted.
    SpotTransaction.new(
      spot_account: @spot_account,
      token: req_params[:token].to_s.strip.presence,
      side: req_params[:side].to_s.strip.downcase.presence,
      executed_at: parse_executed_at(req_params[:executed_at]),
      price_usd: pr,
      amount: amt,
      total_value_usd: (amt && pr ? amt * pr : nil),
      row_signature: SecureRandom.hex(32)
    ).tap(&:validate)
  end

  def load_spot_transactions_filtered
    relation = @spot_account.spot_transactions.newest_first
    relation = relation.where("executed_at >= ?", params[:from_date].to_date.beginning_of_day) if params[:from_date].present?
    relation = relation.where("executed_at <= ?", params[:to_date].to_date.end_of_day) if params[:to_date].present?
    relation = relation.where(token: params[:token]) if params[:token].present?
    relation = relation.where(side: params[:side]) if params[:side].to_s.in?(%w[buy sell])
    relation
  rescue ArgumentError, TypeError
    # Invalid date params: ignore filter
    @spot_account.spot_transactions.newest_first
  end

  def load_index_data
    all_positions = Spot::PositionStateService.call(spot_account: @spot_account)
    open_positions = all_positions.select(&:open?)
    open_tokens = open_positions.map(&:token).uniq
    @current_prices = Spot::CurrentPriceFetcher.call(user: current_user, tokens: open_tokens)
    @positions = open_positions.sort_by { |pos| -( (@current_prices[pos.token] || 0).to_d * pos.balance) }
    @tokens_for_select = tokens_for_select_for(@spot_account)
  end

  def spot_transaction_params
    params.permit(:token, :side, :amount, :price_usd, :executed_at)
  end

  def tokens_for_select_for(spot_account)
    (spot_account.spot_transactions.distinct.pluck(:token) + Spot::TokenList::LIST).uniq.sort
  end
end
