class SessionsController < ActionController::API
  # POST /login
  def login
    @user = User.find_by(name: session_params[:name]).try(:authenticate, session_params[:password])

    if @user
      render json: { token: @user.api_key }
    else
      render json: 'ILUVU', status: :unauthorized
    end
  end

  private

  def session_params
    params.permit(:name, :password)
  end
end