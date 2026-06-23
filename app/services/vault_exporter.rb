require 'fileutils'
require 'yaml'

class VaultExporter
  FILENAME_UNSAFE_REGEX = /[<>:"\/\\|?*\x00-\x1f]/

  attr_reader :user, :output_dir, :exported_count, :created_files, :updated_files, :skipped_files

  def initialize(user, output_dir)
    @user = user
    @output_dir = output_dir
    @exported_count = 0
    @created_files = []
    @updated_files = []
    @skipped_files = []
    @short_id_to_filename = {}
  end

  def export(nodes: nil, since: nil)
    all_nodes = nodes || user.nodes
    FileUtils.mkdir_p(output_dir)

    # First pass: build filename mapping over ALL nodes so links from exported
    # files resolve to filenames of nodes that aren't being re-exported.
    build_filename_mapping(all_nodes)

    # Second pass: export only nodes changed since the last export (when given)
    iterate_nodes(filter_since(all_nodes, since)) do |node|
      export_node(node)
    end

    @exported_count
  end

  # Canonical { short_id => filename (without .md) } for the given nodes.
  # Filenames are derived from headings with short_id dedup for collisions.
  def canonical_filename_map(nodes = nil)
    @short_id_to_filename = {}
    build_filename_mapping(nodes || user.nodes)
    @short_id_to_filename
  end

  def export_node(node)
    filename = @short_id_to_filename[node.short_id]
    filepath = File.join(output_dir, "#{filename}.md")

    content = build_file_content(node)

    existed = File.exist?(filepath)
    if existed && File.read(filepath, mode: 'r:UTF-8') == content
      @skipped_files << filename
      return
    end

    File.write(filepath, content, mode: 'w:UTF-8')
    (existed ? @updated_files : @created_files) << filename
    @exported_count += 1
  end

  private

  def filter_since(nodes, since)
    return nodes if since.nil?

    if nodes.respond_to?(:where)
      nodes.where('updated_at > ?', since)
    else
      nodes.select { |node| node.updated_at && node.updated_at > since }
    end
  end

  def iterate_nodes(nodes, &block)
    if nodes.respond_to?(:find_each)
      nodes.find_each(&block)
    else
      nodes.each(&block)
    end
  end

  def build_filename_mapping(nodes)
    used_filenames = {}

    iterate_nodes(nodes) do |node|
      base_filename = sanitize_filename(node.name)
      filename = base_filename

      # Handle duplicates by appending short_id
      if used_filenames[filename.downcase]
        filename = "#{base_filename} (#{node.short_id})"
      end

      used_filenames[filename.downcase] = true
      @short_id_to_filename[node.short_id] = filename
    end
  end

  def sanitize_filename(name)
    name.gsub(FILENAME_UNSAFE_REGEX, '_').strip.gsub(/\s+/, ' ')
  end

  def build_file_content(node)
    frontmatter = build_frontmatter(node)
    content = convert_links(node.content)

    "#{frontmatter}#{content}"
  end

  def build_frontmatter(node)
    metadata = {
      'short_id' => node.short_id,
      'is_private' => node.is_private,
      'version' => node.version,
      'created_at' => node.created_at&.iso8601,
      'updated_at' => node.updated_at&.iso8601
    }

    metadata['journal_date'] = node.journal_date.iso8601 if node.journal_date
    metadata['slug'] = node.slug if node.slug.present?

    "---\n#{metadata.to_yaml.lines[1..].join}---\n\n"
  end

  def convert_links(content)
    result = content.dup

    # Convert [text](short_id) to [[filename]] for Obsidian compatibility
    result.gsub(LINK_REGEX) do |match|
      text = $1
      target = $2

      # Skip external URLs
      next match if target.start_with?('http')

      target_short_id = target.chomp('!')
      target_filename = @short_id_to_filename[target_short_id]

      if target_filename
        # Use Obsidian wikilink format: [[filename|display text]]
        if text == target_filename
          "[[#{target_filename}]]"
        else
          "[[#{target_filename}|#{text}]]"
        end
      else
        # Keep original if target not found in export set
        match
      end
    end
  end
end
