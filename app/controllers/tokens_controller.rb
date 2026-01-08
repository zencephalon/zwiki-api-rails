class TokensController < ApplicationController
  before_action :require_full_access

  # GET /tokens
  def index
    tokens = @current_user.api_tokens.order(created_at: :desc)
    render json: tokens.map { |t| token_response(t) }
  end

  # POST /tokens/read_only
  def create_read_only
    token = @current_user.create_read_only_token
    render json: token_response(token), status: :created
  end

  # DELETE /tokens/:id
  def destroy
    token = @current_user.api_tokens.find_by(id: params[:id])

    if token.nil?
      render json: { error: 'Token not found' }, status: :not_found
      return
    end

    if token == @current_token
      render json: { error: 'Cannot revoke the token currently in use' }, status: :unprocessable_entity
      return
    end

    token.destroy
    head :no_content
  end

  private

  def token_response(token)
    {
      id: token.id,
      token: token.token,
      token_type: token.token_type,
      expires_at: token.expires_at,
      last_used_at: token.last_used_at,
      created_at: token.created_at
    }
  end
end
