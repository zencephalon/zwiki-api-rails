require 'yaml'

class VaultImporter
  FRONTMATTER_REGEX = /\A---\n(.+?)\n---\n\n?/m
  WIKILINK_REGEX = /\[\[([^\]|]+)(?:\|([^\]]+))?\]\]/

  attr_reader :user, :input_dir
  attr_accessor :created_count, :updated_count, :skipped_count

  def initialize(user, input_dir)
    @user = user
    @input_dir = input_dir
    @created_count = 0
    @updated_count = 0
    @skipped_count = 0
    @filename_to_short_id = {}
  end

  def import(mode: :sync)
    raise ArgumentError, "Directory does not exist: #{input_dir}" unless Dir.exist?(input_dir)

    files = Dir.glob(File.join(input_dir, '*.md'))

    # First pass: build mapping of filenames to short_ids
    build_filename_mapping(files)

    # Second pass: import/sync files
    files.each do |filepath|
      import_file(filepath, mode: mode)
    end

    {
      created: @created_count,
      updated: @updated_count,
      skipped: @skipped_count
    }
  end

  private

  def build_filename_mapping(files)
    files.each do |filepath|
      filename = File.basename(filepath, '.md')
      raw_content = File.read(filepath, encoding: 'UTF-8')
      frontmatter = extract_frontmatter(raw_content)

      if frontmatter && frontmatter['short_id']
        @filename_to_short_id[filename] = frontmatter['short_id']
      end
    end

    # Also map existing user nodes by name
    user.nodes.find_each do |node|
      sanitized_name = sanitize_for_lookup(node.name)
      @filename_to_short_id[sanitized_name] ||= node.short_id
    end
  end

  def sanitize_for_lookup(name)
    name.gsub(/[<>:"\/\\|?*\x00-\x1f]/, '_').strip.gsub(/\s+/, ' ')
  end

  def import_file(filepath, mode:)
    filename = File.basename(filepath, '.md')
    raw_content = File.read(filepath, encoding: 'UTF-8')

    frontmatter = extract_frontmatter(raw_content)
    content = extract_content(raw_content)

    # Convert wikilinks back to zwiki format
    content = convert_wikilinks(content)

    if frontmatter && frontmatter['short_id']
      sync_existing_node(frontmatter, content, filepath, mode: mode)
    else
      create_new_node(filename, frontmatter, content)
    end
  end

  def extract_frontmatter(raw_content)
    match = raw_content.match(FRONTMATTER_REGEX)
    return nil unless match

    YAML.safe_load(match[1], permitted_classes: [Date, Time, DateTime])
  rescue Psych::SyntaxError
    nil
  end

  def extract_content(raw_content)
    raw_content.sub(FRONTMATTER_REGEX, '')
  end

  def convert_wikilinks(content)
    result = content.dup

    result.gsub!(WIKILINK_REGEX) do |match|
      target_filename = $1
      display_text = $2 || target_filename

      target_short_id = @filename_to_short_id[target_filename]

      if target_short_id
        "[#{display_text}](#{target_short_id})"
      else
        # Keep as plain text if target not found
        display_text
      end
    end

    result
  end

  def sync_existing_node(frontmatter, content, filepath, mode:)
    node = user.nodes.find_by(short_id: frontmatter['short_id'])

    unless node
      # Node was deleted from database, create fresh
      create_node_from_frontmatter(frontmatter, content)
      return
    end

    case mode
    when :sync
      update_node(node, content, frontmatter)
    when :force
      update_node(node, content, frontmatter)
    when :skip_existing
      @skipped_count += 1
    end
  end

  def update_node(node, content, frontmatter)
    node.content = content
    node.is_private = frontmatter['is_private'] if frontmatter.key?('is_private')

    unless node.changed?
      @skipped_count += 1
      return
    end

    node.version += 1
    node.save!
    @updated_count += 1
  end

  def create_new_node(filename, frontmatter, content)
    node = user.nodes.new(content: content)

    if frontmatter
      node.is_private = frontmatter.fetch('is_private', true)
    end

    node.save!
    @created_count += 1
  end

  def create_node_from_frontmatter(frontmatter, content)
    node = user.nodes.new(
      content: content,
      is_private: frontmatter.fetch('is_private', true)
    )
    node.save!

    # Try to preserve short_id if possible (no collision)
    unless Node.exists?(short_id: frontmatter['short_id'])
      node.update_column(:short_id, frontmatter['short_id'])
    end

    @created_count += 1
  end
end
