# Binance Futures CSV Import

**Date:** 2026-03-30
**Status:** Approved

## Context

Binance's authenticated API (`fapi.binance.com`) is geo-restricted from Railway's AWS-based servers. The app cannot sync Binance trades automatically. As a first solution (before a potential Cloudflare Worker proxy), users can download their Binance Futures Trade History CSV and upload it manually.

## Architecture and Data Flow

```
CSV file (browser upload)
  → ExchangeAccountsController#import_csv
    → ExchangeAccounts::CsvImportService
        → Exchanges::Binance::CsvParser        (CSV rows → trade hashes)
        → persist_trade per row                (FinancialCalculator + find_or_initialize_by)
        → Positions::RebuildForAccountService  (once, after all rows)
        → Result { created, updated, skipped, errors }
  → redirect with flash notice/alert
```

`CsvImportService` mirrors `Spot::ImportFromCsvService` in structure. No changes to `SyncService`.

The `exchange_reference_id` for each imported trade uses the CSV's `Trade ID` column, which matches what the Binance API returns for the same fill. Re-syncing via API later (if Binance becomes accessible) will not create duplicates.

No `allowed_quote_currencies` filter is applied — manual CSV uploads import all rows regardless of the account whitelist.

## Parser (`Exchanges::Binance::CsvParser`)

**Expected headers:** `Uid, Time, Symbol, Side, Price, Quantity, Amount, Fee, Realized Profit, Buyer, Maker, Trade ID, Order ID`

Raises `ArgumentError` if required columns (`Trade ID`, `Time`, `Symbol`, `Side`, `Price`, `Quantity`, `Fee`) are missing.

**Column mapping:**

| CSV column | Internal field | Handling |
|---|---|---|
| `Trade ID` | `exchange_reference_id` | String, used as-is |
| `Time` | `executed_at` | `YY-MM-DD HH:MM:SS` → parse date only → store as midnight UTC |
| `Symbol` | `symbol` | `BTCUSDC` → `BTC-USDC` via `Binance::TradeNormalizer.normalize_symbol` |
| `Side` | `side` | `BUY`/`SELL` → `"buy"`/`"sell"` |
| `Price` | `price` | BigDecimal |
| `Quantity` | `quantity` | BigDecimal |
| `Fee` | `fee_from_exchange` | `"0.295 USDC"` → split on space → first part as BigDecimal |
| full row | `raw_payload` | Stored as hash |

**Additions to `raw_payload`:**
- `"positionSide" => "BOTH"` — not in CSV, defaults to one-way mode for `PositionSummary`
- `"realizedPnl" => row["Realized Profit"]` — already in CSV, used for closed position PnL display

**Skipped rows:** rows missing `Trade ID` or with an unparseable date are skipped and counted in `skipped`.

**Time handling:** only the date part is stored (exact times are not used anywhere in the platform). `YY-MM-DD HH:MM:SS` → take `YY-MM-DD` → `Date.strptime("%y-%m-%d")` → midnight UTC. No timezone offset handling needed.

## Import Service (`ExchangeAccounts::CsvImportService`)

```ruby
Result = Struct.new(:created, :updated, :skipped, :errors, keyword_init: true)
```

**Flow:**
1. `Binance::CsvParser.call(csv_io)` → array of trade hashes
2. For each hash: `FinancialCalculator.compute(price:, quantity:, side:, fee_from_exchange:)` → `fee`, `net_amount`
3. `account.trades.find_or_initialize_by(exchange_reference_id:)` → new or existing record
4. `assign_attributes` + `save!` → `created` (new record) or `updated` (existing)
5. `rescue ActiveRecord::RecordNotUnique` → `skipped`
6. After all rows: `Positions::RebuildForAccountService.call(account)`

No `last_synced_at` update and no `SyncRun` record created — this is a manual import, not a scheduled sync. The sync status badge is unaffected.

## Route and Controller

**New route:**
```ruby
resources :exchange_accounts do
  member do
    post :sync
    post :historic_sync
    post :import_csv   # new
  end
end
```

**`import_csv` action:**
- `import_csv` added to `set_exchange_account` before_action
- Redirect with alert if `account.provider_type != "binance"`
- Redirect with alert if no file attached
- 10MB file size limit (same as spot CSV)
- Calls `CsvImportService.call(exchange_account: @account, csv_io: params[:csv_file])`
- Success: `"Imported N trade(s), N updated, N skipped."`
- `ArgumentError` (bad headers/format): redirect with the error message as alert

## View (Exchange Accounts Index)

For Binance accounts only (`account.provider_type == "binance"` and `provider_supported`), a second row is added inside the `<li>` below the existing action buttons:

```
[ Choose file ]  [ Import CSV ]
Binance Futures Trade History export (CSV)
```

- `form_with url: import_csv_exchange_account_path(account), method: :post, multipart: true`
- File input accepting `.csv`
- Submit button styled consistently with other action buttons
- The `<li>` layout accommodates both rows (account info + actions on top, CSV form below)

## Tests

**`test/services/exchanges/binance/csv_parser_test.rb`**
- Parses valid CSV fixture → correct field values on trade hashes
- Skips rows missing `Trade ID`
- Skips rows with unparseable date
- Raises `ArgumentError` on missing required headers
- Fee parsing: `"0.29528919 USDC"` → `0.29528919`
- Symbol normalization: `BTCUSDC` → `BTC-USDC`
- `raw_payload` includes `positionSide: "BOTH"` and `realizedPnl`

**`test/services/exchange_accounts/csv_import_service_test.rb`**
- Creates new trades from valid CSV
- Updates existing trades on re-import (idempotent)
- Counts skipped rows correctly
- Calls `Positions::RebuildForAccountService` exactly once
- Does not update `last_synced_at` or create `SyncRun`

**`test/controllers/exchange_accounts_controller_test.rb`** (additions)
- Redirects with alert for non-Binance accounts
- Redirects with alert when no file attached
- Redirects with success notice on valid upload
- Scoped to current user's accounts (404 on another user's account)
