require "rails_helper"

RSpec.describe QuestlogsController, type: :routing do
  describe "routing" do
    it "routes to #index" do
      expect(get: "/questlogs").to route_to("questlogs#index")
    end

    it "routes to #show" do
      expect(get: "/questlogs/1").to route_to("questlogs#show", id: "1")
    end


    it "routes to #create" do
      expect(post: "/questlogs").to route_to("questlogs#create")
    end

    it "routes to #update via PUT" do
      expect(put: "/questlogs/1").to route_to("questlogs#update", id: "1")
    end

    it "routes to #update via PATCH" do
      expect(patch: "/questlogs/1").to route_to("questlogs#update", id: "1")
    end

    it "routes to #destroy" do
      expect(delete: "/questlogs/1").to route_to("questlogs#destroy", id: "1")
    end
  end
end
