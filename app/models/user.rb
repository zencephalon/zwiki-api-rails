class User < ApplicationRecord
  has_secure_password

  has_many :nodes

  # Assign an API key on create
  before_create do |user|
    user.api_key = user.generate_api_key
  end

  after_create do |user|
    node = user.nodes.create(
      name: 'Root',
      content: %{# Root

Welcome to Zwiki

Start creating links to get started.
})
    user.root_id = node.short_id
    user.save
  end

   #ToDO create an after_create to give a root_id of the node id you create for this user

  # Generate a unique API key
  def generate_api_key
    loop do
      token = SecureRandom.base64.tr('+/=', 'Qrt')
      break token unless User.exists?(api_key: token)
    end
  end
end
