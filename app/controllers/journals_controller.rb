class JournalsController < ApplicationController
  skip_before_action :reject_append_only
  before_action :require_append_access

  # POST /journal/today
  def append
    text = params[:text].to_s.strip
    if text.empty?
      render json: { error: 'text is required' }, status: :unprocessable_entity
      return
    end

    node = DailyJournal.new(@current_user).append(text, marker: '🤖')
    render json: { id: node.short_id, name: node.name, version: node.version }, status: :created
  end

  private

  def require_append_access
    return if %w[full_access append_only].include?(@current_token_type)

    render json: { error: 'This endpoint requires append access' }, status: :forbidden
  end
end
