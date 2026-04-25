class ExchangeAccount < ApplicationRecord
  include Discardable
  has_paper_trail on: %i[create update], skip: %i[api_key api_secret settings]

  PROVIDER_TYPES = %w[binance bingx].freeze
  SUPPORTED_QUOTE_CURRENCIES = Exchanges::QuoteCurrencies::SUPPORTED
  DEFAULT_QUOTE_CURRENCIES = Exchanges::QuoteCurrencies::DEFAULT

  store_accessor :settings, :allowed_quote_currencies

  # Custom getter: returns the stored array or the default WITHOUT dirtying the record.
  # Do NOT use after_initialize for this — writing self.x = ... in after_initialize marks
  # `settings` as changed on every ExchangeAccount.find, causing unnecessary UPDATE statements.
  def allowed_quote_currencies
    stored = raw_stored_currencies
    stored.nil? ? DEFAULT_QUOTE_CURRENCIES.dup : stored
  end

  belongs_to :user
  has_many :trades, dependent: :destroy
  has_many :positions, dependent: :destroy
  has_many :sync_runs, dependent: :destroy
  has_many :portfolios, dependent: :nullify

  encrypts :api_key
  encrypts :api_secret

  before_validation :normalize_allowed_quote_currencies

  validate :allowed_quote_currencies_is_array
  validates :allowed_quote_currencies,
    length: { minimum: 1, message: "must contain at least one currency" },
    if: -> { allowed_quote_currencies.is_a?(Array) }
  validate :allowed_quote_currencies_are_valid
  validates :provider_type, inclusion: { in: PROVIDER_TYPES }
  validates :api_key, :api_secret, presence: true

  # Rate limit: max 2 syncs per calendar day (UTC)
  def sync_runs_today_count
    sync_runs.where("ran_at >= ?", Time.current.utc.beginning_of_day).count
  end

  def can_sync?
    user.admin? || user.super_admin? || sync_runs_today_count < 2
  end

  private

  def normalize_allowed_quote_currencies
    raw = raw_stored_currencies
    return unless raw.is_a?(Array)
    return unless raw.all? { |el| el.is_a?(String) || el.is_a?(Symbol) }
    self.allowed_quote_currencies = raw.map { _1.to_s.strip.upcase }.reject(&:empty?).uniq
  end

  def allowed_quote_currencies_is_array
    raw = raw_stored_currencies
    return if raw.nil? || raw.is_a?(Array)
    errors.add(:allowed_quote_currencies, "must be an array")
  end

  def allowed_quote_currencies_are_valid
    raw = raw_stored_currencies
    return unless raw.is_a?(Array)
    invalid = raw - SUPPORTED_QUOTE_CURRENCIES
    errors.add(:allowed_quote_currencies, "contains unknown currencies: #{invalid.join(', ')}") if invalid.any?
  end

  # Single point of access for the raw stored value. Returns nil when the key is absent
  # or when settings is not a Hash (e.g. nil on a brand-new unsaved record).
  def raw_stored_currencies
    settings.is_a?(Hash) ? settings["allowed_quote_currencies"] : nil
  end

end
