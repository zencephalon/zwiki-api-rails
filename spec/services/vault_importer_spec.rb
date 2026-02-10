require 'rails_helper'

RSpec.describe VaultImporter do
  let(:user) { User.create!(name: 'Test', email: 'test@example.com', password: 'password') }
  let(:import_dir) { Rails.root.join('tmp', 'vault_import_test') }

  before do
    FileUtils.rm_rf(import_dir)
    FileUtils.mkdir_p(import_dir)
  end

  after do
    FileUtils.rm_rf(import_dir)
  end

  def write_markdown_file(filename, content, frontmatter = nil)
    filepath = File.join(import_dir, "#{filename}.md")
    file_content = if frontmatter
      "---\n#{frontmatter.to_yaml.lines[1..].join}---\n\n#{content}"
    else
      content
    end
    File.write(filepath, file_content, mode: 'w:UTF-8')
    filepath
  end

  describe '#import' do
    it 'raises an error if directory does not exist' do
      FileUtils.rm_rf(import_dir)
      importer = VaultImporter.new(user, import_dir)

      expect { importer.import }.to raise_error(ArgumentError, /does not exist/)
    end

    it 'creates new nodes from markdown files without frontmatter' do
      write_markdown_file('New Note', "# New Note\n\nSome content here")
      initial_count = user.nodes.count

      importer = VaultImporter.new(user, import_dir)
      result = importer.import

      expect(result[:created]).to eq(1)
      expect(user.nodes.count).to eq(initial_count + 1)

      new_node = user.nodes.find_by(name: 'New Note')
      expect(new_node).to be_present
      expect(new_node.content).to include('Some content here')
    end

    it 'updates existing nodes when content has changed' do
      node = user.nodes.create!(content: "# Existing\n\nOld content")

      write_markdown_file('Existing', "# Existing\n\nNew content", {
        'short_id' => node.short_id,
        'is_private' => true
      })

      importer = VaultImporter.new(user, import_dir)
      result = importer.import(mode: :sync)

      expect(result[:updated]).to eq(1)
      node.reload
      expect(node.content).to include('New content')
    end

    it 'skips nodes when content is unchanged in sync mode' do
      node = user.nodes.create!(content: "# Existing\n\nSame content")

      write_markdown_file('Existing', "# Existing\n\nSame content", {
        'short_id' => node.short_id
      })

      importer = VaultImporter.new(user, import_dir)
      result = importer.import(mode: :sync)

      expect(result[:skipped]).to eq(1)
      expect(node.reload.updated_at).to eq(node.updated_at)
    end

    it 'skips nodes when content is unchanged in force mode' do
      node = user.nodes.create!(content: "# Existing\n\nSame content")

      write_markdown_file('Existing', "# Existing\n\nSame content", {
        'short_id' => node.short_id
      })

      importer = VaultImporter.new(user, import_dir)
      result = importer.import(mode: :force)

      expect(result[:skipped]).to eq(1)
    end

    it 'updates in force mode when content has changed' do
      node = user.nodes.create!(content: "# Existing\n\nOld content")

      write_markdown_file('Existing', "# Existing\n\nForced content", {
        'short_id' => node.short_id
      })

      importer = VaultImporter.new(user, import_dir)
      result = importer.import(mode: :force)

      expect(result[:updated]).to eq(1)
      node.reload
      expect(node.content).to include('Forced content')
    end

    it 'converts Obsidian wikilinks back to zwiki format' do
      target_node = user.nodes.create!(content: "# Target\n\nTarget content")

      write_markdown_file('Source', "# Source\n\nLink to [[Target]]")

      importer = VaultImporter.new(user, import_dir)
      importer.import

      source_node = user.nodes.find_by(name: 'Source')
      expect(source_node.content).to include("[Target](#{target_node.short_id})")
    end

    it 'converts wikilinks with display text' do
      target_node = user.nodes.create!(content: "# Target Page\n\nContent")

      write_markdown_file('Source', "# Source\n\n[[Target Page|click here]]")

      importer = VaultImporter.new(user, import_dir)
      importer.import

      source_node = user.nodes.find_by(name: 'Source')
      expect(source_node.content).to include("[click here](#{target_node.short_id})")
    end

    it 'preserves is_private setting from frontmatter' do
      write_markdown_file('Public Note', "# Public Note\n\nContent", {
        'is_private' => false
      })

      importer = VaultImporter.new(user, import_dir)
      importer.import

      node = user.nodes.find_by(name: 'Public Note')
      expect(node.is_private).to be false
    end

    it 'defaults to private for new nodes without frontmatter' do
      write_markdown_file('Private Note', "# Private Note\n\nContent")

      importer = VaultImporter.new(user, import_dir)
      importer.import

      node = user.nodes.find_by(name: 'Private Note')
      expect(node.is_private).to be true
    end

    it 'returns counts of created, updated, and skipped nodes' do
      existing_node = user.nodes.create!(content: "# Existing\n\nOld")

      write_markdown_file('New Note', "# New Note\n\nNew content")
      write_markdown_file('Existing', "# Existing\n\nUpdated", {
        'short_id' => existing_node.short_id
      })

      importer = VaultImporter.new(user, import_dir)
      result = importer.import

      expect(result[:created]).to eq(1)
      expect(result[:updated]).to eq(1)
    end

    it 'recreates nodes that were deleted from database but exist in vault' do
      write_markdown_file('Deleted Node', "# Deleted Node\n\nRecovered content", {
        'short_id' => 'abc123'
      })

      importer = VaultImporter.new(user, import_dir)
      result = importer.import

      expect(result[:created]).to eq(1)
      node = user.nodes.find_by(name: 'Deleted Node')
      expect(node).to be_present
    end
  end
end
