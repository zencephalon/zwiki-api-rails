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

  describe '#extract_name' do
    it 'reads only the first line so body headings do not hijack untitled nodes' do
      node = user.nodes.create!(content: "plain intro\n\n## Later Heading\nbody")
      expect(node.name).not_to eq('Later Heading')

      titled = user.nodes.create!(content: "# First Line\r\n\r\n## Second")
      expect(titled.name).to eq('First Line')
    end
  end

  describe '#to_export' do
    it 'expands own private inclusions while respecting privacy folds and stripping other users inclusions' do
      snippet = user.nodes.create!(content: "# Snippet\n\nIncluded text ₴ hidden ₴", is_private: true)
      other_user = User.create!(name: 'Other', email: 'other-export@example.com', password: 'password')
      other_public = other_user.nodes.create!(content: "# Other\n\nOTHER USER DATA", is_private: false)
      pub = user.nodes.create!(
        content: "# Public\n\nBefore {s}(#{snippet.short_id}) mid {o}(#{other_public.short_id}) after",
        is_private: false
      )

      exported = pub.to_export
      expect(exported).to include('Before', 'Included text', 'after')
      expect(exported).not_to include('hidden')
      expect(exported).not_to include('OTHER USER DATA')
    end

    it 'terminates on circular inclusions without overflowing the stack' do
      a = user.nodes.create!(content: "# A\n\nbody A", is_private: false)
      b = user.nodes.create!(content: "# B\n\n{a}(#{a.short_id})", is_private: false)
      a.update!(content: "# A\n\n{b}(#{b.short_id})")

      expect { a.to_export }.not_to raise_error
    end

    it 'handles empty content without crashing' do
      expect(Node.to_export("")).to eq("")
      expect(Node.to_export(nil)).to eq("")
    end
  end
end
