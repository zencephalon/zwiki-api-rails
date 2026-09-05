# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a Rails 6.1 API for Zwiki, a personal knowledge management system. The API serves a wiki-like application where users create interconnected nodes (pages) with markdown content and can search, link, and manage their knowledge base.

## Development Commands

### Setup
```bash
bundle install
rails db:create
rails db:migrate
```

### Testing
```bash
bundle exec rspec                    # Run all tests
bundle exec rspec spec/models/       # Run model tests
bundle exec rspec spec/requests/     # Run request tests
bundle exec rspec spec/services/     # Run service tests (agent, vault)
bundle exec rspec spec/path/to/file_spec.rb  # Run specific test file
```

### Development Server
```bash
rails server -p 8000  # zwiki's dev API_BASE expects localhost:8000 (puma defaults to 3000)
```

### Database

The following runs on the server upon deployment: `rails db:migrate && rails server -p $PORT -e ${RAILS_ENV:-production}` so no need to run db:migrate

```bash
rails db:migrate          # Run pending migrations
rails db:rollback         # Rollback last migration
rails console             # Rails console for debugging
```

### Vault (Obsidian) sync
```bash
bundle exec rake vault:export   # all nodes for user 1 → ~/zwiki as markdown with frontmatter
bundle exec rake vault:sync     # import files newer than their DB record
```
Details in `docs/vault-sync.md`.

## Core Architecture

### Models & Relationships

- **User**: Authentication via API keys, owns nodes and questlogs
  - `has_many :nodes, :questlogs`
  - Auto-creates a "Root" node on signup with keyboard shortcuts guide
  - Can designate public nodes via `public_root_id`

- **Node**: The core entity representing wiki pages/knowledge entries
  - Content stored as markdown with auto-extracted titles
  - Uses `short_id` for compact linking (e.g. "ABC123")
  - Supports internal links via `[Link Text](short_id)` syntax
  - Full-text search via PgSearch with highlighting
  - Tagging system for tracking internal links (via acts-as-taggable-on)
  - Privacy controls (`is_private` field)
  - Optimistic locking via `version` field (update rejected if client version ≤ server version)

- **Quest/Questlog**: Secondary features for task/goal tracking

### Key Node Features

1. **Link System**: Nodes can link to each other using `[Text](short_id)` format
2. **Privacy Fold**: Content after `₴` markers is private when exported
3. **Include System**: `{Text}(short_id)` includes content from another node
4. **Auto-naming**: First `# Title` line becomes the node name
5. **Slug Generation**: SEO-friendly URLs from node names
6. **Journal Integration**: Date parsing for journal entries with templates

### API Endpoints

- `GET /nodes` - List/search user's nodes (pass `q` param for search)
- `GET /nodes/search` - Search with single result
- `GET /nodes/full_search_with_summary` - Search with AI-generated summary
- `POST /nodes/:id/append` - Append text to existing node
- `POST /nodes/:id/magic_append` - AI-assisted content merging
- `POST /agent` - Natural-language query over the user's nodes; server-side Claude tool loop, synchronous, may write (see `docs/agent-api.md`)
- `GET /public/node/:slug`, `GET /public/index`, `GET /public/site_index`, `GET /public/root` - Public access, consumed by zencephalon.com
- `POST /login` (`name` + `password`, not email) → `full_access` token, 6-month expiry
- `GET /tokens`, `POST /tokens/read_only`, `DELETE /tokens/:id` - Token management; `read_only` tokens cannot write nodes or use agent write tools
- `GET|PATCH|DELETE /users/me` - Current user only
- Authentication via `Authorization` header containing the **raw token, no `Bearer` prefix**

### External Integrations

- **Anthropic Claude API**: Powers search summaries, magic append, and the `/agent` tool loop (`app/services/zwiki_agent.rb`)
- **zencephalon.com**: `Node#after_save` POSTs `{slug}` to `https://www.zencephalon.com/api/revalidate` with `Bearer $REVALIDATION_TOKEN`; skipped when the env var is blank, so local edits never touch prod
- **PostgreSQL**: Primary database with full-text search
- **pg_search**: Full-text search with highlighting and ranking

### Environment Variables

- `ANTHROPIC_API_KEY`: Required for AI features (search summaries, magic append)
- `REVALIDATION_TOKEN`: Optional; enables the zencephalon revalidation hook above
- Database credentials in `config/database.yml`

## Testing Patterns

- Uses RSpec with FactoryBot for test data
- Test files organized by type: models, requests, routing, services
- Transactional fixtures enabled for clean test isolation
- API testing via request specs, not controller specs for newer endpoints
