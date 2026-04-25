class Admin::Students::BaseController < Admin::BaseController
  before_action :set_student

  private

  def set_student
    @student = User.where(role: "user").find(params[:student_id])
  end
end
