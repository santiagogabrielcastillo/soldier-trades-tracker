class ManualTrade
  include ActiveModel::Model
  include ActiveModel::Attributes

  attribute :symbol,        :string
  attribute :side,          :string      # "buy" or "sell"
  attribute :quantity,      :decimal
  attribute :price,         :decimal
  attribute :executed_at,   :datetime
  attribute :fee,           :decimal,    default: 0
  attribute :position_side, :string      # "LONG" or "SHORT" (optional)
  attribute :leverage,      :integer
  attribute :reduce_only,   :boolean,    default: false
  attribute :realized_pnl,  :decimal,    default: 0

  attr_accessor :exchange_account, :trade_record

  validates :symbol, presence: true,
            format: { with: /\A[A-Z0-9]+-[A-Z0-9]+\z/,
                      message: "must be in BASE-QUOTE format (e.g. BTC-USDT)" }
  validates :side,      presence: true, inclusion: { in: %w[buy sell] }
  validates :quantity,  presence: true, numericality: { greater_than: 0 }
  validates :price,     presence: true, numericality: { greater_than: 0 }
  validates :executed_at, presence: true

  def self.from_trade(trade)
    raw = trade.raw_payload || {}
    new(
      symbol:        trade.symbol,
      side:          raw["side"]&.downcase,
      quantity:      raw["executedQty"]&.to_d,
      price:         raw["avgPrice"]&.to_d,
      executed_at:   trade.executed_at,
      fee:           trade.fee,
      position_side: raw["positionSide"],
      leverage:      trade.leverage_from_raw,
      reduce_only:   raw["reduceOnly"] == true,
      realized_pnl:  raw["profit"]&.to_d || 0
    ).tap { |m| m.trade_record = trade }
  end

  def assign_from_params(attrs)
    assign_attributes(attrs)
  end

  def save
    return false unless valid?
    trade_record ? update_trade_record : create_trade_record
  end

  def persisted? = trade_record&.persisted? || false
  def id         = trade_record&.id

  private

  def create_trade_record
    ts_ms  = (executed_at.to_f * 1000).to_i
    ref_id = "manual_#{ts_ms}_#{SecureRandom.hex(4)}"
    pos_id = "manual_pos_#{ts_ms}_#{SecureRandom.hex(4)}"
    t = Trade.new(
      exchange_account:      exchange_account,
      exchange_reference_id: ref_id,
      symbol:      symbol.upcase,
      side:        side.downcase,
      fee:         fee || 0,
      net_amount:  computed_net_amount,
      executed_at: executed_at,
      position_id: pos_id,
      raw_payload: build_raw_payload(pos_id)
    )
    if t.save
      self.trade_record = t
      true
    else
      t.errors.each { |e| errors.add(e.attribute, e.message) }
      false
    end
  end

  def update_trade_record
    pos_id = trade_record.position_id
    trade_record.assign_attributes(
      symbol:      symbol.upcase,
      side:        side.downcase,
      fee:         fee || 0,
      net_amount:  computed_net_amount,
      executed_at: executed_at,
      raw_payload: build_raw_payload(pos_id)
    )
    if trade_record.save
      true
    else
      trade_record.errors.each { |e| errors.add(e.attribute, e.message) }
      false
    end
  end

  def computed_net_amount
    val = (quantity || 0) * (price || 0)
    side.to_s.downcase == "sell" ? val.abs : -val.abs
  end

  def build_raw_payload(pos_id)
    {
      "side"         => side.upcase,
      "executedQty"  => quantity.to_s,
      "avgPrice"     => price.to_s,
      "positionSide" => position_side.presence&.upcase || (side.downcase == "buy" ? "LONG" : "SHORT"),
      "reduceOnly"   => reduce_only == true,
      "leverage"     => leverage.present? ? "#{leverage}X" : nil,
      "positionID"   => pos_id,
      "profit"       => realized_pnl.to_s
    }.compact
  end
end
