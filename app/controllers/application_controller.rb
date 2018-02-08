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
    @current_user = User.find_by(api_key: token)
    return @current_user
  end

  def render_unauthorized(realm = "Application")
    self.headers["WWW-Authenticate"] = %(Token realm="#{realm.gsub(/"/, "")}")
    render json: 'Bad credentials', status: :unauthorized
  end
end
