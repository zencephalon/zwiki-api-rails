class QuestSerializer < ActiveModel::Serializer
  attributes :id, :blob, :version
  has_one :user
end
