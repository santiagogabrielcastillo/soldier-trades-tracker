class Admin::Students::AllocationManualEntriesController < Admin::Students::BaseController
  before_action :set_entry, only: %i[edit update destroy]

  def index
    @entries = AllocationManualEntry.unscoped.where(user: @student).order(created_at: :desc)
  end

  def new
    @entry   = @student.allocation_manual_entries.build
    @buckets = AllocationBucket.unscoped.where(user: @student).ordered
  end

  def create
    @entry   = @student.allocation_manual_entries.build(entry_params)
    @buckets = AllocationBucket.unscoped.where(user: @student).ordered
    if @entry.save
      redirect_to admin_student_path(@student), notice: "Entry created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @buckets = AllocationBucket.unscoped.where(user: @student).ordered
  end

  def update
    @buckets = AllocationBucket.unscoped.where(user: @student).ordered
    if @entry.update(entry_params)
      redirect_to admin_student_path(@student), notice: "Entry updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @entry.discard!
    redirect_to admin_student_path(@student), notice: "Entry deleted."
  end

  private

  def set_entry
    @entry = AllocationManualEntry.unscoped.find_by!(id: params[:id], user: @student)
  end

  def entry_params
    params.require(:allocation_manual_entry).permit(:label, :amount_usd, :allocation_bucket_id)
  end
end
