class NodeSerializer < ActiveModel::Serializer
  attributes :name, :content, :version
  attribute :short_id, key: :id
end
