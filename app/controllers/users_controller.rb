class UsersController < ApplicationController
  skip_before_action :authenticate, only: [:create]

  # GET /users/me
  def me
    render json: @current_user
  end

  # POST /users
  def create
    @user = User.new(user_params)

    if @user.save
      render json: @user, status: :created
    else
      render json: @user.errors, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /users/me
  def update
    if @current_user.update(user_params)
      render json: @current_user
    else
      render json: @current_user.errors, status: :unprocessable_entity
    end
  end

  # DELETE /users/me
  def destroy
    @current_user.destroy
    head :no_content
  end

  private

  def user_params
    params.require(:user).permit(:name, :email, :password, :password_confirmation)
  end
end
