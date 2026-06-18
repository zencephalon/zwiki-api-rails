require 'yaml'
require 'time'
require 'shellwords'

# Sync-state helpers for incremental vault export/import.
#
# Two redundant signals decide which files `zup` (sync) needs to re-import:
#   1. mtime watermark   - files modified since the last sync (primary)
#   2. `git status`      - files dirty in the vault repo (catches cases where
#                          mtimes were not bumped, e.g. checkouts)
# Their union is imported; if there is no watermark yet we import everything.
module VaultSync
  STATE_FILENAME = '.zwiki-sync.yml'

  module_function

  def vault_dir
    File.expand_path('~/zwiki')
  end

  def state_file(dir)
    File.join(dir, STATE_FILENAME)
  end

  def load_state(dir)
    path = state_file(dir)
    return {} unless File.exist?(path)

    YAML.safe_load(File.read(path)) || {}
  rescue Psych::SyntaxError
    {}
  end

  def save_state(dir, state)
    File.write(state_file(dir), state.to_yaml)
  end

  def git_repo?(dir)
    system("git -C #{dir.shellescape} rev-parse --is-inside-work-tree",
           out: File::NULL, err: File::NULL)
  end

  # Absolute paths of dirty *.md files in the vault repo, or nil if not a repo.
  # Uses NUL-delimited output so paths with spaces/unicode aren't quoted/escaped.
  def git_dirty_md(dir)
    return nil unless git_repo?(dir)

    out = `git -C #{dir.shellescape} status --porcelain -z -- '*.md' 2>/dev/null`
    entries = out.split("\0")
    paths = []
    i = 0
    while i < entries.length
      entry = entries[i]
      i += 1
      next if entry.nil? || entry.empty?

      status = entry[0, 2]
      path = entry[3..].to_s
      i += 1 if status.start_with?('R') || status.start_with?('C') # skip rename/copy source
      paths << File.join(dir, path)
    end
    paths
  end

  # Absolute paths of *.md files modified after `since_iso`, or nil if no watermark.
  def mtime_changed_md(dir, since_iso)
    return nil unless since_iso

    since = Time.parse(since_iso.to_s)
    Dir.glob(File.join(dir, '*.md')).select { |f| File.mtime(f) > since }
  rescue ArgumentError
    nil
  end

  # nil  => no basis yet, import everything (bootstrap)
  # []   => nothing changed
  # [..] => changed files to import
  def changed_md_files(dir, state)
    return nil unless state['last_sync_at']

    files = (mtime_changed_md(dir, state['last_sync_at']) || []) + (git_dirty_md(dir) || [])
    files.uniq.select { |f| f.end_with?('.md') && File.exist?(f) }
  end

  # Rename node-backed files so their filename matches the canonical, heading-
  # derived name (with short_id dedup). Files without frontmatter or without a
  # matching node (e.g. notes that never synced) are left untouched — no data
  # loss, no deletions. Returns the number of files renamed.
  def normalize_filenames(dir, canonical_map)
    renames = []
    Dir.glob(File.join(dir, '*.md')).each do |path|
      base = File.basename(path)
      next if VaultImporter::IGNORED_BASENAMES.include?(base)

      fm = File.read(path, encoding: 'UTF-8')[/\A---\n(.+?)\n---\n/m, 1]
      next unless fm

      sid = fm[/^short_id:\s*(.+)$/, 1]&.strip
      desired = sid && canonical_map[sid]
      next if desired.nil? || "#{desired}.md" == base

      renames << [path, File.join(dir, "#{desired}.md")]
    end

    # Two-phase via temp names so swaps/collisions between renamed files are safe.
    staged = renames.map { |src, dst| [src, dst, "#{src}.zwikitmp#{rand(1_000_000)}"] }
    staged.each { |src, _dst, tmp| File.rename(src, tmp) }
    staged.each { |_src, dst, tmp| File.rename(tmp, dst) }
    renames.size
  end
end

namespace :vault do
  desc "Export nodes for User.find(1) to ~/zwiki (incremental since last export)"
  task export: :environment do
    user = User.find(1)
    dir = VaultSync.vault_dir
    state = VaultSync.load_state(dir)
    started = Time.now.utc
    since = state['last_export_at'] ? Time.parse(state['last_export_at'].to_s) : nil

    puts(since ? "Exporting nodes updated since #{since.iso8601} to #{dir}..."
               : "Exporting all nodes to #{dir}...")

    exporter = VaultExporter.new(user, dir)

    # Keep filenames canonical (filename == heading, with short_id dedup) before
    # writing, so stale-named files are renamed instead of left as duplicates.
    renamed = VaultSync.normalize_filenames(dir, exporter.canonical_filename_map(user.nodes))
    puts "Normalized #{renamed} filename(s)." if renamed.positive?

    count = exporter.export(since: since)

    state['last_export_at'] = started.iso8601
    # After a pull, local files match the server, so nothing is pending upload.
    # Advance the import watermark past the just-written files so the next `zup`
    # doesn't re-scan everything this export rewrote.
    state['last_sync_at'] = Time.now.utc.iso8601
    VaultSync.save_state(dir, state)

    puts "Exported #{count} node(s) to #{dir}"
  end

  desc "Sync nodes for User.find(1) from ~/zwiki (incremental: changed files only)"
  task sync: :environment do
    user = User.find(1)
    dir = VaultSync.vault_dir
    state = VaultSync.load_state(dir)
    started = Time.now.utc

    only_files = VaultSync.changed_md_files(dir, state)
    if only_files.nil?
      puts "No prior sync watermark; importing all files from #{dir}..."
    elsif only_files.empty?
      puts "No changed files since last sync."
    else
      puts "Syncing #{only_files.length} changed file(s) from #{dir}..."
    end

    importer = VaultImporter.new(user, dir)
    result = importer.import(mode: :sync, only_files: only_files)

    state['last_sync_at'] = started.iso8601
    VaultSync.save_state(dir, state)

    puts "Sync complete:"
    puts "  Created: #{result[:created]}"
    puts "  Updated: #{result[:updated]}"
    puts "  Skipped: #{result[:skipped]}"

    failed = result[:failed] || []
    if failed.any?
      puts "  Failed:  #{failed.length}"
      failed.each { |f| puts "    - #{f[:file]}: #{f[:error]}" }
    end
  end

  desc "Rebuild :links/:inclusions tag graph under strict_case_match (one-time)"
  task rebuild_link_tags: :environment do
    user = User.find(1)
    ok = 0; failed = []
    user.nodes.find_each do |node|
      begin
        node.link_list = node.get_links.reject(&:blank?).join(',')
        node.inclusion_list = node.get_inclusions.reject(&:blank?).join(',')
        node.save!
        ok += 1
      rescue => e
        failed << [node.short_id, e.message]
      end
      puts "  ...#{ok} rebuilt" if (ok % 500).zero?
    end
    puts "rebuilt: #{ok}, failed: #{failed.size}"
    failed.first(20).each { |sid, msg| puts "  FAIL #{sid}: #{msg}" }
  end

  desc "Rename vault files so each filename matches its node heading (canonical)"
  task normalize: :environment do
    user = User.find(1)
    dir = VaultSync.vault_dir
    exporter = VaultExporter.new(user, dir)
    renamed = VaultSync.normalize_filenames(dir, exporter.canonical_filename_map(user.nodes))
    puts "Normalized #{renamed} filename(s) in #{dir}."
  end
end
