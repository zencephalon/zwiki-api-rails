class AgentController < ApplicationController
  # POST /agent
  def create
    query = agent_params[:query].to_s
    if query.strip.empty?
      render json: { error: "query is required" }, status: :unprocessable_entity
      return
    end

    agent = ZwikiAgent.new(user: @current_user, allow_writes: @current_token_type == "full_access")
    render json: agent.run(query)
  rescue ZwikiAgent::Error => e
    render json: { error: e.message, tool_calls: agent&.tool_calls || [] }, status: :unprocessable_entity
  rescue Anthropic::Errors::APIStatusError => e
    Rails.logger.error("Agent upstream error #{e.status} #{e.message}")
    render json: { error: "Upstream model error" }, status: :bad_gateway
  end

  private

  def agent_params
    params.permit(:query)
  end
end
