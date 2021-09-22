class NodeSerializer < ActiveModel::Serializer
  attributes :name, :content, :version, :is_private
  attribute :short_id, key: :id
end
