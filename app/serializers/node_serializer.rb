class NodeSerializer < ActiveModel::Serializer
  attributes :id, :name, :content, :version
end
