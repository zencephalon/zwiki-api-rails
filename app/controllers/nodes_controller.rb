class NodesController < ApplicationController
  before_action :set_node, only: [:show, :update, :destroy]

  # GET /nodes
  def index
    q = search_params[:q]
    render json: q ? Node.search_for(q) : Node.all
  end

  # GET /nodes/1
  def show
    render json: @node
  end

  # POST /nodes
  def create
    @node = Node.new(node_params)

    if @node.save
      render json: @node, status: :created, location: @node
    else
      render json: @node.errors, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /nodes/1
  def update
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
    @node.destroy
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_node
      @node = Node.find(params[:id])
    end

    # Only allow a trusted parameter "white list" through.
    def node_params
      params.permit(:name, :content, :id, :title, :version)
    end

    def search_params
      params.permit(:q)
    end
end
