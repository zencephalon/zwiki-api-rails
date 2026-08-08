require 'yaml'

class VaultImporter
  FRONTMATTER_REGEX = /\A---\n(.+?)\n---\n\n?/m
  WIKILINK_REGEX = /\[\[([^\]|]+)(?:\|([^\]]+))?\]\]/

  # Vault-level docs that are not knowledge nodes. Without this they get
  # imported as nodes (named from their heading), duplicating real nodes.
  IGNORED_BASENAMES = %w[CLAUDE.md README.md].freeze

  attr_reader :user, :input_dir
  attr_accessor :created_count, :updated_count, :skipped_count

  def initialize(user, input_dir)
    @user = user
    @input_dir = input_dir
    @created_count = 0
    @updated_count = 0
    @skipped_count = 0
    @failed = []
    @conflicts = []
    @filename_to_short_id = {}
  end

  def import(mode: :sync, only_files: nil)
    raise ArgumentError, "Directory does not exist: #{input_dir}" unless Dir.exist?(input_dir)

    all_files = Dir.glob(File.join(input_dir, '*.md'))
                   .reject { |f| IGNORED_BASENAMES.include?(File.basename(f)) }

    # Load every node once so link resolution and per-file lookups are in-memory
    # instead of one round trip to the database per file.
    preload_nodes

    # First pass: build mapping of filenames to short_ids (needs all files so
    # links from changed files can resolve to unchanged targets)
    build_filename_mapping(all_files)

    # Second pass: import/sync files (only the changed subset when given).
    # A single malformed note must not abort the whole sync.
    files_to_import = only_files || all_files
    files_to_import = files_to_import.reject { |f| IGNORED_BASENAMES.include?(File.basename(f)) }
    files_to_import.each do |filepath|
      begin
        import_file(filepath, mode: mode)
      rescue StandardError => e
        @failed << { file: File.basename(filepath), error: e.message }
      end
    end

    {
      created: @created_count,
      updated: @updated_count,
      skipped: @skipped_count,
      failed: @failed,
      conflicts: @conflicts
    }
  end

  private

  def preload_nodes
    @nodes_by_short_id = {}
    user.nodes.find_each do |node|
      @nodes_by_short_id[node.short_id] = node
    end
  end

  def build_filename_mapping(files)
    files.each do |filepath|
      filename = File.basename(filepath, '.md')
      raw_content = File.read(filepath, encoding: 'UTF-8')
      frontmatter = extract_frontmatter(raw_content)

      if frontmatter && frontmatter['short_id']
        @filename_to_short_id[filename] = frontmatter['short_id']
      end
    end

    # Also map existing user nodes by name (from the preloaded set)
    @nodes_by_short_id.each_value do |node|
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
      sync_existing_node(frontmatter, content, filepath, raw_content, mode: mode)
    elsif (node = resolve_existing_by_filename(filename))
      # No short_id in the file, but its name matches an existing node — update
      # it rather than creating a duplicate on every sync, and stamp the file so
      # future syncs match by short_id directly.
      update_node(node, content, frontmatter || {})
      write_short_id_back(filepath, node, raw_content)
    else
      create_new_node(frontmatter, content, filepath, raw_content)
    end
  end

  def resolve_existing_by_filename(filename)
    short_id = @filename_to_short_id[filename] || @filename_to_short_id[sanitize_for_lookup(filename)]
    short_id && @nodes_by_short_id[short_id]
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

  def sync_existing_node(frontmatter, content, filepath, raw_content, mode:)
    node = @nodes_by_short_id[frontmatter['short_id']]

    unless node
      # Node was deleted from database (or its short_id is stale); create fresh
      create_node_from_frontmatter(frontmatter, content, filepath, raw_content)
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

    if server_moved_ahead?(node, frontmatter)
      @conflicts << {
        file: "#{node.name}.md",
        short_id: node.short_id,
        base_version: frontmatter['version'],
        server_version: current_server_version(node)
      }
      @skipped_count += 1
      return
    end

    node.version += 1
    node.save!
    @updated_count += 1
  end

  # The exporter stamps into each file the version it was pulled at. A server
  # version beyond that means the node changed elsewhere (the Zwiki client)
  # after this file was written, so pushing the file would destroy that work.
  #
  # Read the version straight from the database rather than the preloaded copy,
  # which may have gone stale while earlier files in this run were importing.
  def server_moved_ahead?(node, frontmatter)
    base_version = frontmatter['version']
    return false if base_version.nil?

    current_server_version(node) > base_version.to_i
  end

  def current_server_version(node)
    Node.where(id: node.id).pick(:version) || node.version
  end

  def create_new_node(frontmatter, content, filepath, raw_content)
    node = user.nodes.new(content: content)

    if frontmatter
      node.is_private = frontmatter.fetch('is_private', true)
    end

    node.save!
    @created_count += 1
    write_short_id_back(filepath, node, raw_content)
  end

  def create_node_from_frontmatter(frontmatter, content, filepath, raw_content)
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
    write_short_id_back(filepath, node, raw_content)
  end

  # Stamp the file's frontmatter with the node's live short_id so the next sync
  # matches it directly instead of re-creating it (handles new files and files
  # whose recorded short_id no longer exists).
  #
  # `version` has to travel with it: without a recorded base version the
  # conflict guard in #update_node has nothing to compare against and would let
  # a later stale push overwrite the server.
  def write_short_id_back(filepath, node, raw_content)
    return if raw_content.nil?

    body = raw_content.sub(FRONTMATTER_REGEX, '')
    frontmatter = +"---\nshort_id: #{node.short_id}\n" \
                   "is_private: #{node.is_private}\nversion: #{node.version}\n---\n\n"
    File.write(filepath, frontmatter + body, mode: 'w:UTF-8')
  rescue StandardError
    # Writing back is best-effort; a failure here must not fail the import.
    nil
  end
end
