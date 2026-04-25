class Admin::Students::SpotTransactionsController < Admin::Students::BaseController
  before_action :set_spot_account, only: %i[new create]
  before_action :set_transaction, only: %i[edit update destroy]

  def index
    txns = SpotTransaction.unscoped.where(
      spot_account_id: @student.spot_accounts.select(:id)
    ).order(executed_at: :desc)
    @pagy, @transactions = pagy(:offset, txns, limit: 25)
    @spot_accounts = @student.spot_accounts
  end

  def new
    @transaction = @spot_account.spot_transactions.build
  end

  def create
    @transaction = @spot_account.spot_transactions.build(transaction_params)
    if @transaction.save
      redirect_to admin_student_path(@student), notice: "Transaction created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @spot_account = @transaction.spot_account
  end

  def update
    if @transaction.update(transaction_params)
      redirect_to admin_student_path(@student), notice: "Transaction updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @transaction.discard!
    redirect_to admin_student_path(@student), notice: "Transaction deleted."
  end

  private

  def set_spot_account
    @spot_account = @student.spot_accounts.find_by(id: params[:spot_account_id]) ||
                    @student.spot_accounts.first
    redirect_to admin_student_path(@student), alert: "No spot account found." unless @spot_account
  end

  def set_transaction
    @transaction = SpotTransaction.unscoped.find_by!(
      id: params[:id],
      spot_account_id: @student.spot_accounts.select(:id)
    )
  end

  def transaction_params
    params.require(:spot_transaction).permit(
      :token, :side, :price_usd, :amount, :total_value_usd,
      :executed_at, :notes, :row_signature
    )
  end
end
