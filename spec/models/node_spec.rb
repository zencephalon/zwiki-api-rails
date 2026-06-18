require 'rails_helper'

RSpec.describe Node, type: :model do
  let(:user) { User.create!(name: 'Test', email: 'strict@example.com', password: 'password') }

  describe 'case-sensitive short_id link tags (strict_case_match)' do
    it 'treats short_ids that differ only by case as two distinct :links tags' do
      lower = user.nodes.create!(content: "# Lower\n\nlower content")
      lower.update_column(:short_id, 'dr')

      upper = user.nodes.create!(content: "# Upper\n\nupper content")
      upper.update_column(:short_id, 'dR')

      source = user.nodes.create!(content: "# Source\n\n[low](dr) and [up](dR)")

      # link_list keeps both short_ids verbatim
      expect(source.link_list).to contain_exactly('dr', 'dR')

      # and they resolve to two distinct tag rows, not one folded tag
      tag_names = source.links.map(&:name)
      expect(tag_names).to contain_exactly('dr', 'dR')
      expect(tag_names.uniq.size).to eq(2)

      # backlinks resolve to the correct distinct node for each case
      expect(Node.tagged_with('dr', on: :links)).to include(source)
      expect(Node.tagged_with('dR', on: :links)).to include(source)
    end
  end

  describe '#set_short_id guard' do
    it 'never assigns a short_id containing the problematic İ character' do
      expect(PROBLEMATIC_SHORT_ID_CHARS).to eq(%w[İ])

      # Force the alphabet generator to produce an İ-containing candidate.
      allow(ShortId).to receive(:int_to_short_id).and_return("aİb")

      node = user.nodes.create!(content: "# Guarded\n\nbody")

      expect(node.short_id).not_to include('İ')
      expect(node.short_id).to be_present
    end
  end
end
