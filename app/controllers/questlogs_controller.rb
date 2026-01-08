class QuestlogsController < ApplicationController
  before_action :set_questlog, only: [:show, :update, :destroy]
  before_action :require_full_access, only: [:create, :update, :destroy]

  # GET /questlogs
  def index
    @questlogs = @current_user.questlogs

    render json: @questlogs
  end

  # GET /questlogs/1
  def show
    render json: @questlog
  end

  # POST /questlogs
  def create
    @questlog = @current_user.questlogs.new(questlog_params)

    if @questlog.save
      render json: @questlog, status: :created, location: @questlog
    else
      render json: @questlog.errors, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /questlogs/1
  def update
    if @questlog.update(questlog_params)
      render json: @questlog
    else
      render json: @questlog.errors, status: :unprocessable_entity
    end
  end

  # DELETE /questlogs/1
  def destroy
    @questlog.destroy
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_questlog
      @questlog = @current_user.questlogs.find(params[:id])
    end

    # Only allow a list of trusted parameters through.
    def questlog_params
      params.require(:questlog).permit(:description, :private)
    end
end
