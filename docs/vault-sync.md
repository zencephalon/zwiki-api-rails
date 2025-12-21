# Vault Sync

Export and import Zwiki nodes as Obsidian-compatible markdown files.

## Commands

### Export

```bash
bundle exec rake vault:export
```

Exports all nodes for User ID 1 to `~/zwiki`. Each node becomes a markdown file with:

- YAML frontmatter containing metadata (short_id, is_private, version, timestamps)
- Content with internal links converted to Obsidian wikilinks

### Sync

```bash
bundle exec rake vault:sync
```

Imports changes from `~/zwiki` back to the database. Only updates nodes where the file is newer than the database record.

## File Format

Exported files look like:

```markdown
---
short_id: abc123
is_private: true
version: 3
created_at: '2024-01-15T10:30:00Z'
updated_at: '2024-01-20T14:22:00Z'
---

# Page Title

Content with [[Other Page|link text]] in Obsidian format.
```

## Link Conversion

| Direction | From | To |
|-----------|------|-----|
| Export | `[text](abc123)` | `[[Page Name\|text]]` |
| Import | `[[Page Name]]` | `[Page Name](abc123)` |

## Sync Behavior

- **New files** (no frontmatter): Creates new nodes
- **Existing files** (with short_id): Updates if file mtime > node updated_at
- **Deleted nodes**: Files with short_id not in database are recreated

## Programmatic Usage

```ruby
# Export
exporter = VaultExporter.new(user, '/path/to/vault')
exporter.export

# Import with different modes
importer = VaultImporter.new(user, '/path/to/vault')
importer.import(mode: :sync)          # Update only if file is newer
importer.import(mode: :force)         # Always update
importer.import(mode: :skip_existing) # Only create new nodes
```
