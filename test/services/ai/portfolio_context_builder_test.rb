# frozen_string_literal: true

require "test_helper"

class Ai::PortfolioContextBuilderTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @builder = Ai::PortfolioContextBuilder.new(user: @user)
  end

  test "call returns a non-empty string" do
    stub_empty_services do
      result = @builder.call
      assert_instance_of String, result
      assert result.length > 0
    end
  end

  test "includes date header" do
    stub_empty_services do
      result = @builder.call
      assert_match(/Portfolio context as of/, result)
    end
  end

  test "futures section says no data when no positions" do
    stub_empty_services do
      result = @builder.call
      assert_match(/Crypto Futures/, result)
      assert_match(/No futures positions/, result)
    end
  end

  test "spot section says no data when no positions" do
    stub_empty_services do
      result = @builder.call
      assert_match(/Spot Holdings/, result)
      assert_match(/No spot positions/, result)
    end
  end

  test "stocks section says no data when no positions" do
    stub_empty_services do
      result = @builder.call
      assert_match(/Stock Portfolio/, result)
      assert_match(/No stock positions/, result)
    end
  end

  test "futures section includes position data when positions exist" do
    fake_pos_class = Struct.new(:symbol, :position_side, :entry_price, :net_pl, :open_quantity,
                                :open?, :roi_percent, :leverage, :open_at, :close_at, keyword_init: true)
    open_pos = fake_pos_class.new(
      symbol: "BTC-USDT", position_side: "LONG", entry_price: BigDecimal("50000"),
      net_pl: BigDecimal("1000"), open_quantity: BigDecimal("0.02"),
      open?: true, roi_percent: nil, leverage: 10, open_at: 1.day.ago, close_at: nil
    )

    fake_rel = Object.new
    fake_rel.define_singleton_method(:ordered_for_display) do
      ordered = Object.new
      ordered.define_singleton_method(:to_a) { [open_pos] }
      ordered
    end

    Position.stub(:for_user, ->(_user) { fake_rel }) do
      stub_empty_services(skip_futures: true) do
        result = @builder.call
        assert_match(/BTC-USDT/, result)
        assert_match(/LONG/, result)
      end
    end
  end

  test "watchlist section includes ticker when watchlist has items" do
    ticker = WatchlistTicker.new(ticker: "AAPL")
    mock_rel = Object.new
    mock_rel.define_singleton_method(:ordered) { [ticker] }
    StockFundamental.stub(:for_tickers, ->(_tickers) { {} }) do
      stub_empty_services(watchlist_rel: mock_rel) do
        result = @builder.call
        assert_match(/AAPL/, result)
      end
    end
  end

  private

  def stub_empty_services(skip_futures: false, watchlist_rel: nil)
    empty_ordered = Object.new
    empty_ordered.define_singleton_method(:to_a) { [] }
    empty_rel = Object.new
    empty_rel.define_singleton_method(:ordered_for_display) { empty_ordered }

    spot_stub = ->(_opts) { [] }
    stocks_stub = ->(_opts) { [] }
    allocation_stub = ->(_opts) {
      Allocations::SummaryService::Result.new(buckets: [], total_usd: BigDecimal("0"), unassigned_sources: [])
    }
    default_watchlist_stub = Object.new
    default_watchlist_stub.define_singleton_method(:ordered) { [] }
    watchlist_stub = watchlist_rel || default_watchlist_stub

    if skip_futures
      Spot::PositionStateService.stub(:call, spot_stub) do
        Stocks::PositionStateService.stub(:call, stocks_stub) do
          Allocations::SummaryService.stub(:call, allocation_stub) do
            @user.stub(:watchlist_tickers, watchlist_stub) do
              yield
            end
          end
        end
      end
    else
      Position.stub(:for_user, ->(_user) { empty_rel }) do
        Spot::PositionStateService.stub(:call, spot_stub) do
          Stocks::PositionStateService.stub(:call, stocks_stub) do
            Allocations::SummaryService.stub(:call, allocation_stub) do
              @user.stub(:watchlist_tickers, watchlist_stub) do
                yield
              end
            end
          end
        end
      end
    end
  end
end
