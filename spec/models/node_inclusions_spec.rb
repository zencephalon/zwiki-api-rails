require 'rails_helper'

RSpec.describe Node, type: :model do
  let(:user) { User.create!(name: 'Test', email: 'test@example.com', password: 'password') }

  describe '#get_inclusions' do
    it 'extracts inclusions from content' do
      node = user.nodes.create!(content: "# Test\n\n{Display}(ABC123)")
      expect(node.get_inclusions).to eq(['ABC123'])
    end

    it 'returns empty array when no inclusions' do
      node = user.nodes.create!(content: "# Test\n\nNo inclusions here")
      expect(node.get_inclusions).to eq([])
    end

    it 'extracts multiple inclusions' do
      node = user.nodes.create!(content: "# Test\n\n{One}(ABC)\n\n{Two}(DEF)")
      expect(node.get_inclusions).to eq(['ABC', 'DEF'])
    end

    it 'does not confuse links with inclusions' do
      node = user.nodes.create!(content: "# Test\n\n[Link](ABC123)\n\n{Include}(DEF456)")
      expect(node.get_inclusions).to eq(['DEF456'])
    end
  end

  describe '#tag_inclusions' do
    it 'sets inclusion_list from content on save' do
      target = user.nodes.create!(content: "# Target\n\nTarget content")
      source = user.nodes.create!(content: "# Source\n\n{ref}(#{target.short_id})")

      expect(source.inclusion_list).to eq([target.short_id])
    end

    it 'updates inclusion_list when content changes' do
      target1 = user.nodes.create!(content: "# Target1\n\nContent")
      target2 = user.nodes.create!(content: "# Target2\n\nContent")
      source = user.nodes.create!(content: "# Source\n\n{ref}(#{target1.short_id})")

      expect(source.inclusion_list).to eq([target1.short_id])

      source.update!(content: "# Source\n\n{ref}(#{target2.short_id})")
      expect(source.inclusion_list).to eq([target2.short_id])
    end
  end

  describe '#collect_affected_nodes' do
    it 'finds nodes that directly include this node' do
      included_node = user.nodes.create!(content: "# Included\n\nContent")
      including_node = user.nodes.create!(content: "# Including\n\n{ref}(#{included_node.short_id})")

      affected = included_node.collect_affected_nodes
      expect(affected).to include(including_node)
    end

    it 'finds recursively affected nodes' do
      node_a = user.nodes.create!(content: "# Node A\n\nContent A")
      node_b = user.nodes.create!(content: "# Node B\n\n{ref}(#{node_a.short_id})")
      node_c = user.nodes.create!(content: "# Node C\n\n{ref}(#{node_b.short_id})")

      affected = node_a.collect_affected_nodes
      expect(affected).to include(node_b)
      expect(affected).to include(node_c)
    end

    it 'respects max_depth limit' do
      # Create node_a and set explicit short_id
      node_a = user.nodes.create!(content: "# Node A\n\nContent A")
      node_a.update_column(:short_id, 'NODEA123')

      # Create node_b with inclusion of node_a, then set its short_id
      node_b = user.nodes.build(content: "# Node B\n\n{ref}(NODEA123)")
      node_b.short_id = 'NODEB456'
      node_b.save!

      # Create node_c with inclusion of node_b
      node_c = user.nodes.build(content: "# Node C\n\n{ref}(NODEB456)")
      node_c.short_id = 'NODEC789'
      node_c.save!

      affected = node_a.collect_affected_nodes(max_depth: 1)
      expect(affected.map(&:id)).to include(node_b.id)
      expect(affected.map(&:id)).not_to include(node_c.id)
    end

    it 'handles circular inclusions without infinite loop' do
      node_a = user.nodes.create!(content: "# Node A\n\nContent A")
      node_b = user.nodes.create!(content: "# Node B\n\n{ref}(#{node_a.short_id})")

      # Update node_a to include node_b (circular)
      node_a.update!(content: "# Node A\n\n{ref}(#{node_b.short_id})")

      # Should complete without infinite loop
      affected = node_a.collect_affected_nodes
      expect(affected).to include(node_b)
    end

    it 'returns empty set when no nodes include this one' do
      node = user.nodes.create!(content: "# Lonely\n\nNo one includes me")

      affected = node.collect_affected_nodes
      expect(affected).to be_empty
    end

    it 'does not include nodes that only link (not include) this node' do
      target = user.nodes.create!(content: "# Target\n\nContent")
      linker = user.nodes.create!(content: "# Linker\n\n[link](#{target.short_id})")

      affected = target.collect_affected_nodes
      expect(affected).not_to include(linker)
    end
  end

  describe '#revalidate_cache' do
    before do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('REVALIDATION_TOKEN').and_return('test-token')
    end

    def collect_revalidated_paths
      paths = []
      allow(RestClient::Request).to receive(:execute) do |args|
        payload = JSON.parse(args[:payload])
        paths.concat(Array(payload['paths']))
        double(code: 200)
      end
      paths
    end

    it 'revalidates cache for nodes that include the saved node' do
      included_node = user.nodes.create!(content: "# Included\n\nContent", is_private: false)
      including_node = user.nodes.create!(content: "# Including\n\n{ref}(#{included_node.short_id})", is_private: false)

      revalidated_paths = collect_revalidated_paths
      included_node.update!(content: "# Included\n\nUpdated content")
      sleep(0.2)

      expect(revalidated_paths).to include("/#{included_node.slug}", "/#{including_node.slug}", "/sitemap.xml")
    end

    it 'revalidates cache for recursively affected nodes' do
      node_a = user.nodes.create!(content: "# Node A\n\nContent", is_private: false)
      node_b = user.nodes.create!(content: "# Node B\n\n{ref}(#{node_a.short_id})", is_private: false)
      node_c = user.nodes.create!(content: "# Node C\n\n{ref}(#{node_b.short_id})", is_private: false)

      revalidated_paths = collect_revalidated_paths
      node_a.update!(content: "# Node A\n\nUpdated")
      sleep(0.2)

      expect(revalidated_paths).to include("/#{node_a.slug}", "/#{node_b.slug}", "/#{node_c.slug}")
    end

    it 'skips private nodes and private-only edits when revalidating' do
      included_node = user.nodes.create!(content: "# Included\n\nContent", is_private: false)
      private_includer = user.nodes.create!(content: "# Private\n\n{ref}(#{included_node.short_id})", is_private: false)
      private_includer.update!(is_private: true)
      sleep(0.1)

      revalidated_paths = collect_revalidated_paths
      included_node.update!(content: "# Included\n\nUpdated")
      sleep(0.2)

      expect(revalidated_paths).to include("/#{included_node.slug}")
      expect(revalidated_paths).not_to include("/#{private_includer.slug}")

      revalidated_paths.clear
      private_includer.update!(content: "# Private\n\nStill private")
      sleep(0.2)
      expect(revalidated_paths).to be_empty
    end

    it 'revalidates both old and new slugs on title rename' do
      node = user.nodes.create!(content: "# Old Title\n\nBody", is_private: false)
      old_slug = node.slug

      revalidated_paths = collect_revalidated_paths
      node.update!(content: "# New Title\n\nBody")
      sleep(0.2)

      expect(revalidated_paths).to include("/#{old_slug}", "/#{node.slug}")
    end
  end
end
