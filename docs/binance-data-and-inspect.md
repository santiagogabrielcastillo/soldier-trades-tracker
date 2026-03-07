# Binance data source and DB inspection

## What we pull from Binance

We **only** use the **Futures API** (`https://fapi.binance.com`). We do **not** call spot endpoints. All trades and income are **USDⓈ-M Futures**:

| Source | Endpoint | Purpose |
|--------|----------|--------|
| Symbol discovery (open positions) | `GET /fapi/v2/positionRisk` | Symbols with non-zero `positionAmt` |
| Symbol discovery (historical) | `GET /fapi/v1/income` with `incomeType=REALIZED_PNL` | Every symbol that has a realized PnL in the last 6 months (paginated) |
| Trades | `GET /fapi/v1/userTrades` | Futures trades per symbol, 7-day windows |

So the "many pairs" in your DB are **all futures symbols** that either (1) have an open position now, or (2) had at least one REALIZED_PNL income event in the last 6 months (e.g. you closed a position, or had funding/PnL on that pair). We do **not** import spot trades.

**Why so many symbols?** Income (REALIZED_PNL) includes every futures pair you’ve had a realized PnL event on in the last 6 months (e.g. closed positions, funding). So we request userTrades for all those symbols and store them. If you want to **reduce symbols synced** (e.g. only pairs you currently have open), we can add an option to discover symbols only from position risk (no income), so only symbols with open positions are fetched. That would skip historical closed positions on other pairs.

## Inspect Binance trades in the DB

Run in Rails console or as a rake task:

```ruby
# Binance account and trade counts
account = ExchangeAccount.find_by(provider_type: "binance")
puts "No Binance account" unless account

total = account.trades.count
puts "Total Binance trades: #{total}"

# Trades per symbol (descending)
counts = account.trades.group(:symbol).count.sort_by { |_, c| -c }
puts "\nTrades per symbol (top 20):"
counts.first(20).each { |sym, c| puts "  #{sym}: #{c}" }

# Your one open BTC: find a trade that is the opening leg of an open position (no closing leg yet)
btc_trades = account.trades.where(symbol: "BTC-USDT").order(:executed_at)
puts "\nBTC-USDT trades: #{btc_trades.count}"
# Sample one trade raw payload (e.g. the most recent open)
t = btc_trades.last
if t
  puts "\nSample BTC trade (exchange_reference_id=#{t.exchange_reference_id}):"
  puts t.raw_payload.inspect
  puts "  notional_from_raw: #{t.notional_from_raw}"
  puts "  open_quantity (PositionSummary): raw has qty? #{t.raw_payload['qty'].present?}, executedQty? #{t.raw_payload['executedQty'].present?}"
end
```

To **compare with the API**: call the same endpoint the app uses for one symbol and window:

```ruby
account = ExchangeAccount.find_by(provider_type: "binance")
client = Exchanges::ProviderForAccount.new(account).client
# Same window as your open BTC trade
t = account.trades.where(symbol: "BTC-USDT").order(executed_at: :desc).first
start_ms = (t.executed_at.to_i - 1.day) * 1000
end_ms   = (t.executed_at.to_i + 1.day) * 1000
resp = client.signed_get(Exchanges::BinanceClient::USER_TRADES_PATH,
  "symbol" => "BTCUSDT", "startTime" => start_ms, "endTime" => end_ms, "limit" => 100)
puts "API returned #{resp.size} trades" if resp.is_a?(Array)
puts resp.find { |r| r["id"].to_s == t.exchange_reference_id }&.inspect
```

## Binance raw payload field names

Binance `GET /fapi/v1/userTrades` returns (among others):

- `id`, `symbol`, `orderId`, `side`, `price`, `qty`, `realizedPnl`, `commission`, `time`, `positionSide`, `buyer`, `maker`

BingX uses different names (e.g. `executedQty`, `avgPrice`, `profit`). The app normalizes to a common shape; for margin/ROI we also read from `raw_payload`. We support both: **BingX** (`executedQty`, `avgPrice`, `profit`) and **Binance** (`qty`, `price`, `realizedPnl`) in `Trade` and `PositionSummary` so your one open BTC (and all Binance trades) get correct quantity, notional, and realized PnL.

## How we create Binance trades (no income as trades)

We **only** create `Trade` records from **GET /fapi/v1/userTrades** (actual fills). We do **not** import income records as trades.

1. **Symbol discovery:** Symbols from `positionRisk` (open positions) and `income` with `incomeType=REALIZED_PNL` (last 6 months). Format is Binance style (e.g. `COMPUSDT`).
2. **Fetch:** For each symbol we call userTrades with 7-day windows and `symbol=COMPUSDT`. We only get trades for that symbol.
3. **Normalize:** `Binance::TradeNormalizer.user_trade_to_hash` uses `id`, `symbol` → `COMP-USDT`, `side`, `price`, `qty`, `commission`, `time` → `executed_at`, full payload as `raw_payload`, `position_id` from `positionSide`.
4. **Persist:** `SyncService` saves by `exchange_reference_id`; `net_amount` is from price × qty and fee. PnL in the UI uses `raw_payload["realizedPnl"]` when present.

So every COMP-USDT row in the DB came from a Binance userTrades response for `COMPUSDT`. If you see trades you do not recognize (e.g. Shorts after your close), they are what Binance returned; you can confirm in Binance Futures → Trade History (COMPUSDT).

## Auditing one symbol (e.g. COMP-USDT)

Run in Rails console to list all trades for a symbol by date and side:

```ruby
account = ExchangeAccount.find_by(provider_type: "binance")
symbol = "COMP-USDT"
trades = account.trades.where(symbol: symbol).order(:executed_at)
puts "Total #{symbol} trades: #{trades.count}"
puts "%4s %-12s %-6s %12s %20s" % [ "id", "executed_at", "side", "realizedPnl", "exchange_reference_id" ]
trades.each do |t|
  r = t.raw_payload || {}
  pnl = r["realizedPnl"] || r["realized_pnl"]
  puts "%4d %-12s %-6s %12s %20s" % [ t.id, t.executed_at&.strftime("%Y-%m-%d"), t.side, pnl.to_s, t.exchange_reference_id ]
end
puts "\nBy side: BUY=#{trades.count { |t| t.side.to_s.upcase == 'BUY' }}, SELL=#{trades.count { |t| t.side.to_s.upcase == 'SELL' }}"
```

If you see SELLs after your close date, those are what Binance returned for COMPUSDT; the app does not add or invent trades.

## position_id "BOTH" (one-way mode)

Binance Futures **one-way mode** sends `positionSide: "BOTH"` for every trade. We **group by symbol first**, then by position_id and split chains per symbol. That way COMP, BTC, ROSE, etc. each get their own positions; we never mix symbols in one BOTH bucket. We store that as `position_id`. If we grouped all trades with `position_id = "BOTH"` into one bucket, we would merge unrelated positions (e.g. an old closed position and your current open BTC) into a single “position.” So we **split by position chains**: for each symbol we sort trades by time and compute running quantity (buy +, sell −). Each time running qty **crosses zero**, the next trade starts a new chain. Each chain is then passed to the same position-summary logic (one open + its closes), so you get one row per closed leg and correct open positions. See `PositionSummary.split_both_chains` and `from_trades` in `app/models/position_summary.rb`.
