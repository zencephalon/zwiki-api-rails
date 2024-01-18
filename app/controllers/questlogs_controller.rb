class QuestlogsController < ApplicationController
  before_action :set_questlog, only: [:show, :update, :destroy]

  # GET /questlogs
  def index
    @questlogs = Questlog.all

    render json: @questlogs
  end

  # GET /questlogs/1
  def show
    render json: @questlog
  end

  # POST /questlogs
  def create
    @questlog = Questlog.new(questlog_params)

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
      @questlog = Questlog.find(params[:id])
    end

    # Only allow a list of trusted parameters through.
    def questlog_params
      params.require(:questlog).permit(:user_id, :description, :private)
    end
end
