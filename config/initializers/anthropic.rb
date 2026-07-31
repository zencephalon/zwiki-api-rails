# The anthropic gem calls BaseModel.subclasses while loading, and redefines
# BaseModel.== to compare lazily-resolved field thunks. ActiveSupport 6.1's
# Class#subclasses override (removed in Rails 7.1, which uses Ruby's native
# implementation) routes through ==, so those thunks resolve mid-load and blow
# up on Anthropic::Beta constants that do not exist yet.
#
# Swap in an identity-comparing equivalent of Ruby's native Class#subclasses for
# the duration of the require, then hand the method table back to ActiveSupport.
# Drop this file once the app is on Rails 7.1+.
activesupport_subclasses = Class.instance_method(:subclasses)

Class.class_eval do
  def subclasses
    ObjectSpace.each_object(singleton_class).select do |klass|
      !klass.singleton_class? && !klass.equal?(self) && klass.superclass.equal?(self)
    end
  end
end

begin
  require "anthropic"
ensure
  Class.send(:define_method, :subclasses, activesupport_subclasses)
end
