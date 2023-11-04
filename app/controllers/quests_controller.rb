class QuestsController < ApplicationController
  before_action :set_quest, only: [:show, :update, :destroy]

  # GET /quests/1
  def show
    render json: @quest
  end

  # POST /quests
  # def create
  #   @quest = Quest.new(quest_params)

  #   if @quest.save
  #     render json: @quest, status: :created, location: @quest
  #   else
  #     render json: @quest.errors, status: :unprocessable_entity
  #   end
  # end

  # PATCH/PUT /quests/1
  def update
    if @quest.update(blob: quest_params[:blob])
      render json: @quest
    else
      render json: @quest.errors, status: :unprocessable_entity
    end
  end

  # DELETE /quests/1
  def destroy
    @quest.destroy
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_quest
      @quest = Quest.find_by(user_id: @current_user.id)
      if @quest.nil?
        @quest = Quest.new(user_id: @current_user.id, blob: {})
        @quest.save
      end
    end

    # Only allow a list of trusted parameters through.
    def quest_params
      params.permit(:blob)
    end
end
