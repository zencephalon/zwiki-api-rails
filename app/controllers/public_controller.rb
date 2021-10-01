class PublicController < ApplicationController

  def index
    render json: @current_user.public_slugs
  end

  def show
    node = Node.find_by(slug: public_params[:slug])

    if !node or node.is_private
      render json: "private", status: :unprocessable_entity
      return
    end
 
    render json: {
      content: node.to_export,
      name: node.name,
      slug: node.slug,
    }
  end

  private

    def public_params
      params.permit(:slug)
    end
end
