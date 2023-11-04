class QuestSerializer < ActiveModel::Serializer
  attributes :id, :blob
  has_one :user
end
