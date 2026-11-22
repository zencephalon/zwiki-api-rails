class SessionsController < ActionController::API
  # POST /login
  def login
    @user = User.find_by(name: session_params[:name]).try(:authenticate, session_params[:password])

    if @user
      api_token = @user.create_full_access_token
      render json: {
        token: api_token.token,
        expires_at: api_token.expires_at
      }
    else
      render json: 'ILUVU', status: :unauthorized
    end
  end

  private

  def session_params
    params.permit(:name, :password)
  end
end