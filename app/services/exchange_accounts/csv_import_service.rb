# frozen_string_literal: true

class ExchangeAccounts::CsvImportService
  Result = Struct.new(:created, :updated, :skipped, :errors, keyword_init: true)

  def self.call(exchange_account:, csv_io:)
    new(exchange_account: exchange_account, csv_io: csv_io).call
  end

  def initialize(exchange_account:, csv_io:)
    @account = exchange_account
    @csv_io  = csv_io
  end

  def call
    trades = parse_csv!
    created = 0
    updated = 0
    skipped = 0
    errors  = []

    trades.each_with_index do |attrs, idx|
      outcome = persist_trade(attrs, idx + 2)
      case outcome
      when :created then created += 1
      when :updated then updated += 1
      when :skipped then skipped += 1
      when String   then errors << outcome
      end
    end

    Positions::RebuildForAccountService.call(@account)
    Result.new(created: created, updated: updated, skipped: skipped, errors: errors)
  end

  private

  def parse_csv!
    Exchanges::Binance::CsvParser.call(@csv_io)
  rescue Exchanges::Binance::CsvParser::ParseError => e
    raise ArgumentError, e.message
  end

  def persist_trade(attrs, row_number)
    computed = Exchanges::FinancialCalculator.compute(
      price:             attrs[:price],
      quantity:          attrs[:quantity],
      side:              attrs[:side],
      fee_from_exchange: attrs[:fee_from_exchange]
    )

    trade      = @account.trades.find_or_initialize_by(exchange_reference_id: attrs[:exchange_reference_id])
    new_record = trade.new_record?

    trade.assign_attributes(
      symbol:      attrs[:symbol],
      side:        attrs[:side],
      fee:         computed[:fee],
      net_amount:  computed[:net_amount],
      executed_at: attrs[:executed_at],
      raw_payload: attrs[:raw_payload] || {}
    )
    trade.save!
    new_record ? :created : :updated
  rescue ActiveRecord::RecordNotUnique
    :skipped
  rescue ActiveRecord::RecordInvalid => e
    "Row #{row_number}: #{e.message}"
  end
end
