class NodesController < ApplicationController
  before_action :set_node, only: [:show, :update, :destroy]

  # GET /nodes
  def index
    q = search_params[:q]
    render json: q.empty? ? @current_user.nodes.all : @current_user.nodes.search_for(q), each_serializer: NodeShortSerializer
  end

  # GET /nodes/1
  def show
    if @current_user.id == @node.user_id
      render json: @node
    else
      render json: @node.errors, status: :unprocessable_entity
    end
  end

  # POST /nodes
  def create
    node = Node.find_by(name: node_params[:name])

    if node
      render json: node, location: node
      return
    end

    @node = Node.new(node_params)
    @node.user_id = @current_user.id

    if @node.save
      render json: @node, status: :created, location: @node
    else
      render json: @node.errors, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /nodes/1
  def update
    if @current_user.id != @node.user_id
      render status: :forbidden
    end
    if @node.version >= node_params[:version].to_i
      render json: { server_version: @node.version, client_version: node_params[:version] }, status: :unprocessable_entity
      return
    end
    if @node.update(node_params)
      render json: @node
    else
      render json: @node.errors, status: :unprocessable_entity
    end
  end

  # DELETE /nodes/1
  def destroy
    if @current_user.id != @node.user_id
      render status: :forbidden
    end

    @node.destroy
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_node
      @node = @current_user.nodes.find_by(short_id: params[:id])
    end

    # Only allow a trusted parameter "white list" through.
    def node_params
      params.permit(:name, :content, :title, :version, :node)
    end

    def search_params
      params.permit(:q)
    end
end
