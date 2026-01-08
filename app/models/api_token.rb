class ApiToken < ApplicationRecord
  belongs_to :user

  TOKEN_TYPES = %w[read_only full_access].freeze
  FULL_ACCESS_EXPIRY = 7.days

  validates :token, presence: true, uniqueness: true
  validates :token_type, presence: true, inclusion: { in: TOKEN_TYPES }

  scope :read_only, -> { where(token_type: 'read_only') }
  scope :full_access, -> { where(token_type: 'full_access') }
  scope :active, -> { where('expires_at IS NULL OR expires_at > ?', Time.current) }

  before_validation :generate_token, on: :create

  def expired?
    expires_at.present? && expires_at < Time.current
  end

  def read_only?
    token_type == 'read_only'
  end

  def full_access?
    token_type == 'full_access'
  end

  def touch_last_used
    update_column(:last_used_at, Time.current)
  end

  private

  def generate_token
    return if token.present?

    loop do
      self.token = SecureRandom.base64(32).tr('+/=', 'Qrt')
      break unless ApiToken.exists?(token: token)
    end
  end
end
