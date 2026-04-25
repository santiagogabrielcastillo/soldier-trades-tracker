class Admin::Students::SpotAccountsController < Admin::Students::BaseController
  before_action :set_account, only: %i[edit update destroy]

  def index
    @accounts = SpotAccount.unscoped.where(user: @student)
  end

  def new
    @account = @student.spot_accounts.build
  end

  def create
    @account = @student.spot_accounts.build(account_params)
    if @account.save
      redirect_to admin_student_path(@student), notice: "Spot account created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @account.update(account_params)
      redirect_to admin_student_path(@student), notice: "Spot account updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @account.discard!
    redirect_to admin_student_path(@student), notice: "Spot account deleted."
  end

  private

  def set_account
    @account = SpotAccount.unscoped.find_by!(id: params[:id], user: @student)
  end

  def account_params
    params.require(:spot_account).permit(:name)
  end
end
