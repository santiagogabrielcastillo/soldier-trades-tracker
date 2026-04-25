class Admin::Students::ExchangeAccountsController < Admin::Students::BaseController
  before_action :set_account, only: %i[edit update destroy]

  def index
    @accounts = ExchangeAccount.unscoped.where(user: @student)
  end

  def new
    @account = @student.exchange_accounts.build
  end

  def create
    @account = @student.exchange_accounts.build(account_params)
    if @account.save
      redirect_to admin_student_path(@student), notice: "Exchange account created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @account.update(account_params)
      redirect_to admin_student_path(@student), notice: "Exchange account updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @account.discard!
    redirect_to admin_student_path(@student), notice: "Exchange account deleted."
  end

  private

  def set_account
    @account = ExchangeAccount.unscoped.find_by!(id: params[:id], user: @student)
  end

  def account_params
    params.require(:exchange_account).permit(:provider_type, :api_key, :api_secret)
  end
end
