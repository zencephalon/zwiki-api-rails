class QuestlogSerializer < ActiveModel::Serializer
  attributes :id, :description, :private
  has_one :user
end
