class UserSerializer < ActiveModel::Serializer
  attributes :id, :name, :email, :root_id
end
