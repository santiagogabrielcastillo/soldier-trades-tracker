class Admin::Students::TradesController < Admin::Students::BaseController
  before_action :set_trade, only: %i[edit update destroy]

  def index
    trades = Trade.unscoped.where(
      exchange_account_id: @student.exchange_accounts.select(:id)
    ).order(executed_at: :desc)
    @pagy, @trades = pagy(:offset, trades, limit: 25)
    @exchange_accounts = @student.exchange_accounts
  end

  def new
    @trade = ManualTrade.new
    @exchange_accounts = @student.exchange_accounts
  end

  def create
    @exchange_accounts = @student.exchange_accounts
    account = @student.exchange_accounts.find_by(id: params[:exchange_account_id])
    unless account
      redirect_to admin_student_path(@student), alert: "Exchange account not found." and return
    end
    @trade = ManualTrade.new(trade_params)
    @trade.exchange_account = account
    if @trade.save
      Positions::RebuildForAccountService.call(account)
      redirect_to admin_student_path(@student), notice: "Trade created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @exchange_accounts = @student.exchange_accounts
  end

  def update
    account = @trade.trade_record.exchange_account
    @exchange_accounts = @student.exchange_accounts
    @trade.assign_from_params(trade_params)
    if @trade.save
      Positions::RebuildForAccountService.call(account)
      redirect_to admin_student_path(@student), notice: "Trade updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    account = @trade.trade_record.exchange_account
    @trade.trade_record.discard!
    Positions::RebuildForAccountService.call(account)
    redirect_to admin_student_path(@student), notice: "Trade deleted."
  end

  private

  def set_trade
    record = Trade.unscoped.where(
      exchange_account_id: @student.exchange_accounts.select(:id)
    ).find(params[:id])
    @trade = ManualTrade.from_trade(record)
  end

  def trade_params
    params.require(:manual_trade).permit(
      :symbol, :side, :quantity, :price, :executed_at,
      :fee, :position_side, :leverage, :reduce_only, :realized_pnl
    )
  end
end
