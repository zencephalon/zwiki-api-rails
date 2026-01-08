class ApplicationController < ActionController::API
  include ActionController::Serialization

  include ActionController::HttpAuthentication::Token::ControllerMethods

  before_action :authenticate

  protected

  # Authenticate the user with token based authentication
  def authenticate
    authenticate_token || render_unauthorized
  end

  def authenticate_token
    token = request.headers['Authorization']
    return false unless token

    # Try new api_tokens table first
    api_token = ApiToken.includes(:user).find_by(token: token)
    if api_token
      return false if api_token.expired?
      api_token.touch_last_used
      @current_user = api_token.user
      @current_token = api_token
      @current_token_type = api_token.token_type
      return @current_user
    end

    # Fallback to legacy api_key for backwards compatibility
    @current_user = User.find_by(api_key: token)
    @current_token_type = 'full_access' if @current_user  # Legacy tokens have full access
    return @current_user
  end

  def require_full_access
    return true if @current_token_type == 'full_access'
    render json: { error: 'This endpoint requires full access' }, status: :forbidden
    false
  end

  def render_unauthorized(realm = "Application")
    self.headers["WWW-Authenticate"] = %(Token realm="#{realm.gsub(/"/, "")}")
    render json: 'Bad credentials', status: :unauthorized
  end
end
