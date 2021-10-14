class PublicController < ApplicationController

  def index
    render json: @current_user.public_slugs.to_json
  end

  def site_index
    render json: @current_user.public_index.to_json
  end

  def show
    node = @current_user.nodes.find_by(slug: public_params[:slug])

    if !node or node.is_private
      render json: "private", status: :unprocessable_entity
      return
    end
 
    render json: node.next_json
  end

  def root
    render json: @current_user.public_root.next_json
  end

  private

    def public_params
      params.permit(:slug)
    end
end
