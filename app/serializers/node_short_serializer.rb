class NodeShortSerializer < ActiveModel::Serializer
  attributes :name, :version
  attribute :short_id, key: :id
end
