require "rails_helper"

RSpec.describe UsersController, type: :routing do
  describe "routing" do
    it "routes to #me" do
      expect(get: "/users/me").to route_to("users#me")
    end

    it "routes to #create" do
      expect(post: "/users").to route_to("users#create")
    end

    it "routes to #update via PUT" do
      expect(put: "/users/me").to route_to("users#update")
    end

    it "routes to #update via PATCH" do
      expect(patch: "/users/me").to route_to("users#update")
    end

    it "routes to #destroy" do
      expect(delete: "/users/me").to route_to("users#destroy")
    end

    it "does not route to #index" do
      expect(get: "/users").not_to be_routable
    end

    it "does not route to #show by id" do
      expect(get: "/users/1").not_to be_routable
    end
  end
end
