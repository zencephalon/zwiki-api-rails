class NodesController < ApplicationController
  before_action :set_node, only: [:show, :update, :destroy, :append, :magic_append]

  # GET /nodes
  def index
    q = search_params[:q]
    render json: q.empty? ? @current_user.nodes.all : @current_user.nodes.search_for(q), each_serializer: NodeShortSerializer
  end

  def search
    q = search_params[:q]
    render json: q.empty? ? [] : @current_user.nodes.search_for(q).limit(1), each_serializer: NodeSerializer
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
    node = @current_user.nodes.find_by(name: node_params[:name])

    if node
      render json: node, location: node
      return
    end

    @node = @current_user.nodes.new(node_params)

    unless @node.content
      @node.content = "# " + @node.name + "\n\n"
      if @node.is_day_entry
        day_template = @current_user.nodes.find_by(name: '__journal_template__')

        if day_template
          @node.content += day_template.content_without_title
        end
      end
    end

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

  def append
    if @current_user.id != @node.user_id
      render status: :forbidden
    end
    text = params.permit(:text)[:text]
    @node.append(text)
    if @node.save
      render json: @node
    else
      render json: @node.errors, status: :unprocessable_entity
    end
  end

  def magic_append
    if @current_user.id != @node.user_id
      render status: :forbidden
      return
    end

    text = magic_append_params[:text]
    
    client = Anthropic::Client.new(access_token: ENV['ANTHROPIC_API_KEY'])
    
    system_prompt = "You assist the user's personal knowledge management system. You'll be given a new journal entry and an existing knowledge entry. Update it to reflect the new information. Always include events that occurred. Filter extraneous information. Don't elaborate or extrapolate. Keep the pre-existing content intact unless it needs modification to reflect the new information. Return only the updated Markdown."
    
    message = "#{text}\n\n============================\n\n#{@node.content}"
    
    response = client.messages(
      parameters: {
        model: "claude-3-5-sonnet-20241022",
        system: system_prompt,
        messages: [
          { role: "user", content: message }
        ],
        max_tokens: 2000
      }
    )

    ai_response = response["content"].first["text"]

    puts ai_response
    
    if ai_response
      @node.content = ai_response
      @node.version = @node.version + 1
      if @node.save
        render json: @node
      else
        render json: @node.errors, status: :unprocessable_entity
      end
    else
      render json: { error: "Failed to get AI response" }, status: :unprocessable_entity
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
      params.permit(:name, :content, :title, :version, :node, :is_private)
    end

    def search_params
      params.permit(:q)
    end

    def magic_append_params
      params.permit(:text, :id, :node)
    end
end
