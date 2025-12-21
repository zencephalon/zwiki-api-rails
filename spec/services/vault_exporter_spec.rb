require 'rails_helper'

RSpec.describe VaultExporter do
  let(:user) { User.create!(name: 'Test', email: 'test@example.com', password: 'password') }
  let(:export_dir) { Rails.root.join('tmp', 'vault_export_test') }

  before do
    FileUtils.rm_rf(export_dir)
  end

  after do
    FileUtils.rm_rf(export_dir)
  end

  describe '#export' do
    it 'creates the output directory if it does not exist' do
      exporter = VaultExporter.new(user, export_dir)
      exporter.export

      expect(Dir.exist?(export_dir)).to be true
    end

    it 'exports nodes as markdown files with frontmatter' do
      node = user.nodes.create!(content: "# Test Node\n\nSome content here")

      exporter = VaultExporter.new(user, export_dir)
      exporter.export

      filepath = File.join(export_dir, 'Test Node.md')
      expect(File.exist?(filepath)).to be true

      content = File.read(filepath)
      expect(content).to include('---')
      expect(content).to include("short_id: #{node.short_id}")
      expect(content).to include('# Test Node')
      expect(content).to include('Some content here')
    end

    it 'handles duplicate node names by appending short_id' do
      node1 = user.nodes.create!(content: "# Same Name\n\nFirst node")
      node2 = user.nodes.create!(content: "# Same Name\n\nSecond node")

      exporter = VaultExporter.new(user, export_dir)
      exporter.export

      files = Dir.glob(File.join(export_dir, '*.md'))
      expect(files.length).to eq(3) # 2 + root node from user creation

      filenames = files.map { |f| File.basename(f) }
      expect(filenames).to include('Same Name.md')
      expect(filenames.any? { |f| f.include?(node1.short_id) || f.include?(node2.short_id) }).to be true
    end

    it 'converts internal links to Obsidian wikilinks' do
      target_node = user.nodes.create!(content: "# Target Page\n\nTarget content")
      source_node = user.nodes.create!(content: "# Source Page\n\nLink to [Target](#{target_node.short_id})")

      exporter = VaultExporter.new(user, export_dir)
      exporter.export(nodes: [source_node, target_node])

      filepath = File.join(export_dir, 'Source Page.md')
      content = File.read(filepath)

      expect(content).to include('[[Target Page|Target]]')
    end

    it 'preserves external URLs' do
      node = user.nodes.create!(content: "# Test\n\n[Google](https://google.com)")

      exporter = VaultExporter.new(user, export_dir)
      exporter.export(nodes: [node])

      filepath = File.join(export_dir, 'Test.md')
      content = File.read(filepath)

      expect(content).to include('[Google](https://google.com)')
    end

    it 'includes metadata in frontmatter' do
      node = user.nodes.create!(content: "# Test\n\nContent", is_private: false)

      exporter = VaultExporter.new(user, export_dir)
      exporter.export(nodes: [node])

      filepath = File.join(export_dir, 'Test.md')
      content = File.read(filepath)

      expect(content).to include('is_private: false')
      expect(content).to include('version:')
      expect(content).to include('created_at:')
      expect(content).to include('updated_at:')
    end

    it 'sanitizes unsafe filename characters' do
      node = user.nodes.create!(content: "# Test/Node:With<Bad>Chars\n\nContent")

      exporter = VaultExporter.new(user, export_dir)
      exporter.export(nodes: [node])

      files = Dir.glob(File.join(export_dir, '*.md'))
      filenames = files.map { |f| File.basename(f) }

      expect(filenames.any? { |f| f.include?('/') }).to be false
      expect(filenames.any? { |f| f.include?(':') }).to be false
    end

    it 'returns the count of exported nodes' do
      user.nodes.create!(content: "# Node 1\n\nContent")
      user.nodes.create!(content: "# Node 2\n\nContent")

      exporter = VaultExporter.new(user, export_dir)
      count = exporter.export

      expect(count).to eq(3) # 2 + root node
    end
  end
end
