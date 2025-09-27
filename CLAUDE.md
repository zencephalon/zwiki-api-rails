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
bundle exec rspec spec/controllers/  # Run controller tests
bundle exec rspec spec/requests/     # Run request tests
bundle exec rspec spec/path/to/file_spec.rb  # Run specific test file
```

### Development Server
```bash
rails server  # Start development server on port 3000
```

### Database
```bash
rails db:migrate          # Run pending migrations
rails db:rollback         # Rollback last migration
rails console             # Rails console for debugging
```

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
  - Tagging system for tracking internal links
  - Privacy controls (`is_private` field)
  - Versioning with conflict detection

- **Quest/Questlog**: Secondary features for task/goal tracking

### Key Node Features

1. **Link System**: Nodes can link to each other using `[Text](short_id)` format
2. **Privacy Fold**: Content after `₴` markers is private when exported
3. **Include System**: `{Text}(short_id)` includes content from another node
4. **Auto-naming**: First `# Title` line becomes the node name
5. **Slug Generation**: SEO-friendly URLs from node names
6. **Journal Integration**: Date parsing for journal entries with templates

### API Endpoints

- `GET /nodes` - List/search user's nodes
- `GET /nodes/search` - Search with single result
- `GET /nodes/full_search_with_summary` - Search with AI-generated summary
- `POST /nodes/:id/append` - Append text to existing node
- `POST /nodes/:id/magic_append` - AI-assisted content merging
- `GET /public/node/:slug` - Public node access
- Authentication via `api_key` header

### External Integrations

- **Anthropic Claude API**: Powers search summaries and magic append features
- **PostgreSQL**: Primary database with full-text search
- **pg_search**: Full-text search with highlighting and ranking

### Environment Variables

- `ANTHROPIC_API_KEY`: Required for AI features (search summaries, magic append)
- Database credentials in `config/database.yml`

## Testing Patterns

- Uses RSpec with FactoryBot for test data
- Test files organized by type: models, controllers, requests, routing
- Transactional fixtures enabled for clean test isolation
- API testing via request specs, not controller specs for newer endpoints