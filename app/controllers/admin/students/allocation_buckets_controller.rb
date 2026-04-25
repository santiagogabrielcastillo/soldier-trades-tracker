class Admin::Students::AllocationBucketsController < Admin::Students::BaseController
  before_action :set_bucket, only: %i[edit update destroy]

  def index
    @buckets = AllocationBucket.unscoped.where(user: @student).ordered
  end

  def new
    @bucket = @student.allocation_buckets.build
  end

  def create
    @bucket = @student.allocation_buckets.build(bucket_params)
    if @bucket.save
      redirect_to admin_student_path(@student), notice: "Allocation bucket created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @bucket.update(bucket_params)
      redirect_to admin_student_path(@student), notice: "Allocation bucket updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @bucket.discard!
    redirect_to admin_student_path(@student), notice: "Allocation bucket deleted."
  end

  private

  def set_bucket
    @bucket = AllocationBucket.unscoped.find_by!(id: params[:id], user: @student)
  end

  def bucket_params
    params.require(:allocation_bucket).permit(:name, :color, :target_pct)
  end
end
