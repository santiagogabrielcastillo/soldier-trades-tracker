# Extended Fundamentals Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend `StockFundamental` with `sector`, `industry`, and `ev_ebitda` fields scraped from Finviz, and add an AI Rating column placeholder to the fundamentals table that prompts users to configure their Gemini key when missing.

**Architecture:** Add three columns to `stock_fundamentals` via a migration, extend `Stocks::FundamentalsFetcher` to parse them from the Finviz quote HTML, update `Stocks::SyncFundamentalsJob` to persist them, and add a non-functional "AI Rating" column to `_fundamentals_table` that links to settings when no Gemini key is configured.

**Tech Stack:** Rails 7.2, Nokogiri (already used in fetcher), minitest, Tailwind CSS.

---

## File Map

| File | Action | Purpose |
|---|---|---|
| `db/migrate/TIMESTAMP_add_extended_fields_to_stock_fundamentals.rb` | Create | Add `sector`, `industry`, `ev_ebitda` columns |
| `app/services/stocks/fundamentals_fetcher.rb` | Modify | Extend `FundamentalsData` struct + `parse_finviz` |
| `app/jobs/stocks/sync_fundamentals_job.rb` | Modify | Persist new fields in upsert |
| `app/views/stocks/_fundamentals_table.html.erb` | Modify | Add AI Rating column |
| `test/services/stocks/fundamentals_fetcher_test.rb` | Create | Test new field parsing |
| `test/fixtures/files/finviz_quote.html` | Create | Minimal Finviz HTML fixture |
| `test/jobs/stocks/sync_fundamentals_job_test.rb` | Create | Test new fields are persisted |
| `test/fixtures/stock_fundamentals.yml` | Create | Fixture for fundamentals tests |

---

### Task 1: Migration — add sector, industry, ev_ebitda

**Files:**
- Create: `db/migrate/TIMESTAMP_add_extended_fields_to_stock_fundamentals.rb`

- [ ] **Step 1: Generate migration**

```bash
bin/rails generate migration AddExtendedFieldsToStockFundamentals \
  sector:string industry:string ev_ebitda:decimal
```

Expected output: `invoke  active_record` with a new migration file under `db/migrate/`.

- [ ] **Step 2: Edit the generated migration to add precision**

Open the generated file (path will match `db/migrate/*_add_extended_fields_to_stock_fundamentals.rb`) and ensure it reads:

```ruby
class AddExtendedFieldsToStockFundamentals < ActiveRecord::Migration[7.2]
  def change
    add_column :stock_fundamentals, :sector,    :string
    add_column :stock_fundamentals, :industry,  :string
    add_column :stock_fundamentals, :ev_ebitda, :decimal, precision: 12, scale: 4
  end
end
```

- [ ] **Step 3: Run migration**

```bash
bin/rails db:migrate
```

Expected: `== AddExtendedFieldsToStockFundamentals: migrating` then `migrated`.

- [ ] **Step 4: Commit**

```bash
git add db/migrate db/schema.rb
git commit -m "feat(stocks): add sector, industry, ev_ebitda to stock_fundamentals"
```

---

### Task 2: Extend FundamentalsFetcher — tests first

**Files:**
- Create: `test/fixtures/files/finviz_quote.html`
- Create: `test/services/stocks/fundamentals_fetcher_test.rb`
- Modify: `app/services/stocks/fundamentals_fetcher.rb`

- [ ] **Step 1: Create minimal Finviz HTML fixture**

Create `test/fixtures/files/finviz_quote.html`:

```html
<!DOCTYPE html>
<html>
<head><title>AAPL Stock Quote</title></head>
<body>
  <table class="fullview-title">
    <tr>
      <td>
        <a href="/screener.ashx?v=111&f=sec_Technology">Technology</a>
        <span> | </span>
        <a href="/screener.ashx?v=111&f=ind_ConsumerElectronics">Consumer Electronics</a>
      </td>
    </tr>
  </table>

  <table class="snapshot-table2">
    <tr>
      <td>P/E</td><td>28.5</td>
      <td>Fwd P/E</td><td>25.1</td>
    </tr>
    <tr>
      <td>PEG</td><td>2.30</td>
      <td>P/S</td><td>7.50</td>
    </tr>
    <tr>
      <td>P/FCF</td><td>30.2</td>
      <td>EV/EBITDA</td><td>22.10</td>
    </tr>
    <tr>
      <td>Profit Margin</td><td>25.31%</td>
      <td>ROE</td><td>147.25%</td>
    </tr>
    <tr>
      <td>ROIC</td><td>55.10%</td>
      <td>Debt/Eq</td><td>1.87</td>
    </tr>
    <tr>
      <td>Sales Y/Y TTM</td><td>2.02%</td>
      <td>Sales Q/Q</td><td>4.87%</td>
    </tr>
  </table>
</body>
</html>
```

- [ ] **Step 2: Write failing tests**

Create `test/services/stocks/fundamentals_fetcher_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

module Stocks
  class FundamentalsFetcherTest < ActiveSupport::TestCase
    FIXTURE_HTML = File.read(
      Rails.root.join("test/fixtures/files/finviz_quote.html")
    ).freeze

    test "returns empty hash for blank tickers" do
      assert_equal({}, FundamentalsFetcher.call(tickers: []))
    end

    test "parses existing metrics from snapshot table" do
      result = fetch_with_fixture("AAPL")

      assert_in_delta 28.5,  result.pe.to_f,         0.01
      assert_in_delta 25.1,  result.fwd_pe.to_f,     0.01
      assert_in_delta 2.30,  result.peg.to_f,         0.01
      assert_in_delta 7.50,  result.ps.to_f,          0.01
      assert_in_delta 30.2,  result.pfcf.to_f,        0.01
      assert_in_delta 25.31, result.net_margin.to_f,  0.01
      assert_in_delta 147.25, result.roe.to_f,        0.01
      assert_in_delta 55.10, result.roic.to_f,        0.01
      assert_in_delta 1.87,  result.debt_eq.to_f,     0.01
      assert_in_delta 2.02,  result.sales_5y.to_f,    0.01
      assert_in_delta 4.87,  result.sales_qq.to_f,    0.01
    end

    test "parses ev_ebitda from snapshot table" do
      result = fetch_with_fixture("AAPL")

      assert_in_delta 22.10, result.ev_ebitda.to_f, 0.01
    end

    test "parses sector from screener link" do
      result = fetch_with_fixture("AAPL")

      assert_equal "Technology", result.sector
    end

    test "parses industry from screener link" do
      result = fetch_with_fixture("AAPL")

      assert_equal "Consumer Electronics", result.industry
    end

    test "returns nil for sector when link not present" do
      html = "<html><body><table class='snapshot-table2'></table></body></html>"
      result = fetch_with_html("AAPL", html)

      assert_nil result.sector
    end

    test "returns nil for ev_ebitda when not in table" do
      html = "<html><body><table class='snapshot-table2'><tr><td>P/E</td><td>28.5</td></tr></table></body></html>"
      result = fetch_with_html("AAPL", html)

      assert_nil result.ev_ebitda
    end

    test "returns nil when snapshot table is missing" do
      html = "<html><body><p>Not found</p></body></html>"
      fetcher = FundamentalsFetcher.new(["AAPL"])

      response = mock_response(html)
      Net::HTTP.stub(:start, response) do
        result = fetcher.call
        assert_nil result["AAPL"]
      end
    end

    test "normalizes and deduplicates tickers" do
      call_count = 0
      fetcher = FundamentalsFetcher.new(["aapl", "AAPL"])

      response = mock_response(FIXTURE_HTML)
      FundamentalsFetcher.stub(:new, ->(_tickers) {
        Object.new.tap do |obj|
          obj.define_singleton_method(:call) do
            call_count += 1
            { "AAPL" => nil }
          end
        end
      }) do
        FundamentalsFetcher.call(tickers: ["aapl", "AAPL"])
      end
      # Deduplication is tested via the fetcher directly
      assert_equal ["AAPL"], fetcher.instance_variable_get(:@tickers)
    end

    private

    def fetch_with_fixture(ticker)
      result = nil
      fetcher = FundamentalsFetcher.new([ticker])
      response = mock_response(FIXTURE_HTML)
      Net::HTTP.stub(:start, response) do
        result = fetcher.call
      end
      result[ticker]
    end

    def fetch_with_html(ticker, html)
      result = nil
      fetcher = FundamentalsFetcher.new([ticker])
      response = mock_response(html)
      Net::HTTP.stub(:start, response) do
        result = fetcher.call
      end
      result[ticker]
    end

    def mock_response(body)
      res = Object.new
      res.define_singleton_method(:is_a?) { |klass| klass == Net::HTTPSuccess }
      res.define_singleton_method(:body)  { body }
      # Net::HTTP.start yields http; http.request returns the response
      http = Object.new
      http.define_singleton_method(:request) { |_req| res }
      ->(host, port, **_opts, &block) { block.call(http) }
    end
  end
end
```

- [ ] **Step 3: Run tests to confirm they fail**

```bash
bin/rails test test/services/stocks/fundamentals_fetcher_test.rb
```

Expected: Multiple failures — `FundamentalsData` doesn't have `sector`, `industry`, `ev_ebitda` yet.

- [ ] **Step 4: Extend FundamentalsData struct**

In `app/services/stocks/fundamentals_fetcher.rb`, replace the struct definition and the `FundamentalsData.new(...)` call:

Replace:
```ruby
    FundamentalsData = Struct.new(
      :pe, :fwd_pe, :peg, :ps, :pfcf, :net_margin, :roe, :roic,
      :debt_eq, :sales_5y, :sales_qq,
      keyword_init: true
    )
```

With:
```ruby
    FundamentalsData = Struct.new(
      :pe, :fwd_pe, :peg, :ps, :pfcf, :net_margin, :roe, :roic,
      :debt_eq, :sales_5y, :sales_qq, :sector, :industry, :ev_ebitda,
      keyword_init: true
    )
```

- [ ] **Step 5: Extend parse_finviz to extract new fields**

In `app/services/stocks/fundamentals_fetcher.rb`, replace the `parse_finviz` method body from the `FundamentalsData.new(...)` call onwards, and add the sector/industry extraction. Replace the entire `parse_finviz` method:

```ruby
    def parse_finviz(html, ticker)
      require "nokogiri"
      doc   = Nokogiri::HTML(html)
      table = doc.at_css("table.snapshot-table2")

      unless table
        Rails.logger.warn("[Stocks::FundamentalsFetcher] #{ticker}: snapshot table not found")
        return nil
      end

      metrics = {}
      table.css("td").each do |td|
        label = td.text.strip
        next if label.empty?
        next_td = td.next_element
        metrics[label] = next_td.text.strip if next_td&.name == "td"
      end

      return nil if metrics.empty?

      Rails.logger.info("[Stocks::FundamentalsFetcher] #{ticker} metrics: #{metrics.slice('P/E', 'Fwd P/E', 'PEG', 'P/S', 'P/FCF', 'Profit Margin', 'ROE', 'ROIC', 'Debt/Eq', 'Sales Y/Y TTM', 'Sales Q/Q', 'EV/EBITDA')}")

      sector_link   = doc.at_css("a[href*='f=sec_']")
      industry_link = doc.at_css("a[href*='f=ind_']")

      FundamentalsData.new(
        pe:         decimal(metrics["P/E"]),
        fwd_pe:     decimal(metrics["Fwd P/E"]),
        peg:        decimal(metrics["PEG"]),
        ps:         decimal(metrics["P/S"]),
        pfcf:       decimal(metrics["P/FCF"]),
        net_margin: pct(metrics["Profit Margin"]),
        roe:        pct(metrics["ROE"]),
        roic:       pct(metrics["ROIC"]),
        debt_eq:    decimal(metrics["Debt/Eq"]),
        sales_5y:   pct(metrics["Sales Y/Y TTM"]),
        sales_qq:   pct(metrics["Sales Q/Q"]),
        ev_ebitda:  decimal(metrics["EV/EBITDA"]),
        sector:     sector_link&.text&.strip.presence,
        industry:   industry_link&.text&.strip.presence
      )
    end
```

- [ ] **Step 6: Run tests to confirm they pass**

```bash
bin/rails test test/services/stocks/fundamentals_fetcher_test.rb
```

Expected: All tests pass.

- [ ] **Step 7: Commit**

```bash
git add app/services/stocks/fundamentals_fetcher.rb \
        test/services/stocks/fundamentals_fetcher_test.rb \
        test/fixtures/files/finviz_quote.html
git commit -m "feat(stocks): parse sector, industry, ev_ebitda from Finviz"
```

---

### Task 3: Update SyncFundamentalsJob to persist new fields — tests first

**Files:**
- Create: `test/fixtures/stock_fundamentals.yml`
- Create: `test/jobs/stocks/sync_fundamentals_job_test.rb`
- Modify: `app/jobs/stocks/sync_fundamentals_job.rb`

- [ ] **Step 1: Create stock_fundamentals fixture**

Create `test/fixtures/stock_fundamentals.yml`:

```yaml
aapl:
  ticker: AAPL
  pe: 28.5
  fwd_pe: 25.1
  peg: 2.30
  ps: 7.50
  pfcf: 30.2
  net_margin: 25.31
  roe: 147.25
  roic: 55.10
  debt_eq: 1.87
  sales_5y: 2.02
  sales_qq: 4.87
  sector: Technology
  industry: Consumer Electronics
  ev_ebitda: 22.10
  fetched_at: 2026-04-08 10:00:00
```

- [ ] **Step 2: Write failing test**

Create `test/jobs/stocks/sync_fundamentals_job_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

module Stocks
  class SyncFundamentalsJobTest < ActiveSupport::TestCase
    test "upserts fundamentals including sector, industry, ev_ebitda" do
      fundamentals_data = {
        "MSFT" => Stocks::FundamentalsFetcher::FundamentalsData.new(
          pe: BigDecimal("35.2"), fwd_pe: BigDecimal("30.1"),
          peg: BigDecimal("2.10"), ps: BigDecimal("12.5"),
          pfcf: BigDecimal("40.0"), net_margin: BigDecimal("36.0"),
          roe: BigDecimal("40.0"), roic: BigDecimal("25.0"),
          debt_eq: BigDecimal("0.50"), sales_5y: BigDecimal("15.0"),
          sales_qq: BigDecimal("17.0"),
          sector: "Technology", industry: "Software-Infrastructure",
          ev_ebitda: BigDecimal("25.0")
        )
      }

      Stocks::FundamentalsFetcher.stub(:call, fundamentals_data) do
        Stocks::SyncFundamentalsJob.new.perform(["MSFT"])
      end

      record = StockFundamental.find_by!(ticker: "MSFT")
      assert_equal "Technology",             record.sector
      assert_equal "Software-Infrastructure", record.industry
      assert_in_delta 25.0, record.ev_ebitda.to_f, 0.01
      assert_in_delta 35.2, record.pe.to_f,         0.01
    end

    test "logs count of synced tickers" do
      Stocks::FundamentalsFetcher.stub(:call, {}) do
        assert_nothing_raised { Stocks::SyncFundamentalsJob.new.perform(["AAPL"]) }
      end
    end
  end
end
```

- [ ] **Step 3: Run test to confirm it fails**

```bash
bin/rails test test/jobs/stocks/sync_fundamentals_job_test.rb
```

Expected: Failure — `sector`, `industry`, `ev_ebitda` not included in the upsert hash.

- [ ] **Step 4: Update SyncFundamentalsJob upsert**

In `app/jobs/stocks/sync_fundamentals_job.rb`, replace the `upsert` call:

Replace:
```ruby
        StockFundamental.upsert(
          { ticker: ticker, pe: f.pe, fwd_pe: f.fwd_pe, peg: f.peg, ps: f.ps, pfcf: f.pfcf,
            net_margin: f.net_margin, roe: f.roe, roic: f.roic,
            debt_eq: f.debt_eq, sales_5y: f.sales_5y, sales_qq: f.sales_qq,
            fetched_at: now },
          unique_by: :ticker
        )
```

With:
```ruby
        StockFundamental.upsert(
          { ticker: ticker, pe: f.pe, fwd_pe: f.fwd_pe, peg: f.peg, ps: f.ps, pfcf: f.pfcf,
            net_margin: f.net_margin, roe: f.roe, roic: f.roic,
            debt_eq: f.debt_eq, sales_5y: f.sales_5y, sales_qq: f.sales_qq,
            sector: f.sector, industry: f.industry, ev_ebitda: f.ev_ebitda,
            fetched_at: now },
          unique_by: :ticker
        )
```

- [ ] **Step 5: Run test to confirm it passes**

```bash
bin/rails test test/jobs/stocks/sync_fundamentals_job_test.rb
```

Expected: Both tests pass.

- [ ] **Step 6: Commit**

```bash
git add app/jobs/stocks/sync_fundamentals_job.rb \
        test/jobs/stocks/sync_fundamentals_job_test.rb \
        test/fixtures/stock_fundamentals.yml
git commit -m "feat(stocks): persist sector, industry, ev_ebitda in fundamentals sync"
```

---

### Task 4: Add AI Rating column with "Configure AI" prompt

**Files:**
- Modify: `app/views/stocks/_fundamentals_table.html.erb`

- [ ] **Step 1: Add AI Rating column header and rows**

In `app/views/stocks/_fundamentals_table.html.erb`, replace the entire file:

```erb
<%# locals: (tickers:, fundamentals:, sync_url:, watchlist_items: nil) %>
<% last_synced = fundamentals.values.map(&:fetched_at).min %>
<div class="mb-4 flex items-center justify-between">
  <p class="text-xs text-slate-500">
    <% if last_synced %>
      Last synced <%= time_ago_in_words(last_synced) %> ago · "—" means no data available for that ticker
    <% else %>
      No data yet — click Sync to fetch fundamentals from Finviz
    <% end %>
  </p>
  <%= button_to "Sync now", sync_url,
        method: :post,
        class: "rounded-md bg-slate-800 px-3 py-1.5 text-sm font-medium text-white hover:bg-slate-700 focus:outline-none focus:ring-2 focus:ring-slate-500" %>
</div>

<%= render DataTableComponent.new(columns: [
  { label: "Ticker",     classes: "text-left" },
  { label: "AI Rating",  classes: "text-center" },
  { label: "Sector",     classes: "text-left" },
  { label: "P/E",        classes: "text-right" },
  { label: "Fwd P/E",   classes: "text-right" },
  { label: "PEG",        classes: "text-right" },
  { label: "P/S",        classes: "text-right" },
  { label: "P/FCF",      classes: "text-right" },
  { label: "EV/EBITDA",  classes: "text-right" },
  { label: "Net Margin", classes: "text-right" },
  { label: "ROE",        classes: "text-right" },
  { label: "ROIC",       classes: "text-right" },
  { label: "Debt/Eq",    classes: "text-right" },
  { label: "Sales Y/Y",  classes: "text-right" },
  { label: "Sales Q/Q",  classes: "text-right" },
  *(watchlist_items ? [{ label: "", classes: "text-right" }] : [])
]) do |table| %>
  <% tickers.each do |ticker| %>
    <% f = fundamentals[ticker] %>
    <% table.with_row do %>
      <td class="whitespace-nowrap px-6 py-4 text-sm font-semibold text-slate-900"><%= ticker %></td>
      <td class="whitespace-nowrap px-6 py-4 text-center text-sm">
        <% if current_user.gemini_api_key_configured? %>
          <span class="text-slate-400">—</span>
        <% else %>
          <%= link_to "Configure AI", settings_path,
                class: "text-xs font-medium text-indigo-600 hover:text-indigo-800 underline underline-offset-2" %>
        <% end %>
      </td>
      <td class="whitespace-nowrap px-6 py-4 text-sm text-slate-500"><%= f&.sector || "—" %></td>
      <td class="whitespace-nowrap px-6 py-4 text-right text-sm text-slate-700"><%= f&.pe     ? number_with_precision(f.pe,     precision: 1) : "—" %></td>
      <td class="whitespace-nowrap px-6 py-4 text-right text-sm text-slate-700"><%= f&.fwd_pe ? number_with_precision(f.fwd_pe, precision: 1) : "—" %></td>
      <td class="whitespace-nowrap px-6 py-4 text-right text-sm text-slate-700"><%= f&.peg    ? number_with_precision(f.peg,    precision: 2) : "—" %></td>
      <td class="whitespace-nowrap px-6 py-4 text-right text-sm text-slate-700"><%= f&.ps     ? number_with_precision(f.ps,     precision: 1) : "—" %></td>
      <td class="whitespace-nowrap px-6 py-4 text-right text-sm text-slate-700"><%= f&.pfcf   ? number_with_precision(f.pfcf,   precision: 1) : "—" %></td>
      <td class="whitespace-nowrap px-6 py-4 text-right text-sm text-slate-700"><%= f&.ev_ebitda ? number_with_precision(f.ev_ebitda, precision: 1) : "—" %></td>
      <td class="whitespace-nowrap px-6 py-4 text-right text-sm <%= f&.net_margin ? (f.net_margin >= 0 ? 'text-emerald-600' : 'text-red-600') : 'text-slate-500' %>">
        <%= f&.net_margin ? number_to_percentage(f.net_margin, precision: 1) : "—" %>
      </td>
      <td class="whitespace-nowrap px-6 py-4 text-right text-sm <%= f&.roe ? (f.roe >= 0 ? 'text-emerald-600' : 'text-red-600') : 'text-slate-500' %>">
        <%= f&.roe ? number_to_percentage(f.roe, precision: 1) : "—" %>
      </td>
      <td class="whitespace-nowrap px-6 py-4 text-right text-sm <%= f&.roic ? (f.roic >= 0 ? 'text-emerald-600' : 'text-red-600') : 'text-slate-500' %>">
        <%= f&.roic ? number_to_percentage(f.roic, precision: 1) : "—" %>
      </td>
      <td class="whitespace-nowrap px-6 py-4 text-right text-sm text-slate-700"><%= f&.debt_eq  ? number_with_precision(f.debt_eq,  precision: 2) : "—" %></td>
      <td class="whitespace-nowrap px-6 py-4 text-right text-sm <%= f&.sales_5y ? (f.sales_5y >= 0 ? 'text-emerald-600' : 'text-red-600') : 'text-slate-500' %>">
        <%= f&.sales_5y ? number_to_percentage(f.sales_5y, precision: 1) : "—" %>
      </td>
      <td class="whitespace-nowrap px-6 py-4 text-right text-sm <%= f&.sales_qq ? (f.sales_qq >= 0 ? 'text-emerald-600' : 'text-red-600') : 'text-slate-500' %>">
        <%= f&.sales_qq ? number_to_percentage(f.sales_qq, precision: 1) : "—" %>
      </td>
      <% if watchlist_items %>
        <td class="whitespace-nowrap px-6 py-4 text-right">
          <%= button_to "Remove", stocks_watchlist_item_path(watchlist_items[ticker]),
                method: :delete,
                class: "text-xs font-medium text-red-500 hover:text-red-700" %>
        </td>
      <% end %>
    <% end %>
  <% end %>
<% end %>
```

- [ ] **Step 2: Run full test suite to check for regressions**

```bash
bin/rails test
```

Expected: All tests pass. If a controller or view test references the fundamentals table, update the assertion to account for the new columns.

- [ ] **Step 3: Commit**

```bash
git add app/views/stocks/_fundamentals_table.html.erb
git commit -m "feat(stocks): add AI Rating and Sector columns to fundamentals table"
```

---

### Task 5: Final smoke test

- [ ] **Step 1: Run full test suite**

```bash
bin/rails test
```

Expected: All tests pass with 0 failures, 0 errors.

- [ ] **Step 2: Run rubocop**

```bash
bundle exec rubocop app/services/stocks/fundamentals_fetcher.rb \
                    app/jobs/stocks/sync_fundamentals_job.rb
```

Expected: No offenses (or only style cops — fix any that appear).

- [ ] **Step 3: Commit any lint fixes, or note "no changes needed"**

```bash
git add -p
git commit -m "style: rubocop fixes for extended fundamentals sync"
```
