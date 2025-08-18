# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Mastodon fork (TheConnector) - a free, open-source social network server based on ActivityPub. The codebase is a full-stack web application with:
- **Backend**: Ruby on Rails API server
- **Frontend**: React.js with Redux for dynamic UI
- **Streaming**: Node.js server for real-time updates via WebSockets
- **Database**: PostgreSQL for data storage, Redis for caching/queues
- **Search**: Elasticsearch integration via Chewy gem

## Key Development Commands

### Setup & Installation
```bash
# Install dependencies
bundle install              # Ruby gems
yarn install                # Node packages

# Database setup
RAILS_ENV=development bin/setup  # Initial setup
bin/rails db:migrate       # Run migrations
bin/rails db:seed          # Seed data
```

### Development
```bash
bin/dev                    # Start all services (Rails, Vite, Streaming)
yarn dev                   # Start Vite dev server only
bin/rails server          # Rails server only
node streaming/index.js    # Streaming server only
```

### Testing
```bash
# JavaScript/TypeScript
yarn test                  # Run all tests (lint, typecheck, unit tests)
yarn lint                  # ESLint + Stylelint
yarn typecheck            # TypeScript type checking
yarn test:js              # Vitest unit tests

# Ruby/Rails
bundle exec rspec         # Run RSpec tests
bundle exec rubocop       # Ruby linting
```

### Building
```bash
yarn build:production     # Production build with Vite
yarn build:development    # Development build
docker buildx build .     # Docker build
```

## Architecture & Code Structure

### Core Directories

**Backend (Rails)**
- `app/controllers/` - HTTP request handlers, split between web UI and API
- `app/models/` - ActiveRecord models (Account, Status, User, etc.)
- `app/services/` - Business logic services (post creation, federation, etc.)
- `app/workers/` - Sidekiq background jobs
- `app/lib/` - Core utilities and ActivityPub implementation
- `app/serializers/` - API response formatting
- `app/policies/` - Authorization policies using Pundit

**Frontend (React)**
- `app/javascript/mastodon/` - Main React application
- `app/javascript/mastodon/components/` - Reusable React components
- `app/javascript/mastodon/features/` - Feature-specific components (timeline, compose, etc.)
- `app/javascript/mastodon/actions/` - Redux action creators
- `app/javascript/mastodon/reducers/` - Redux state management
- `app/javascript/mastodon/locales/` - i18n translations

**Streaming Server**
- `streaming/` - Node.js WebSocket server for real-time updates

### Key Models & Concepts

- **Account**: Represents both local and remote user accounts
- **Status**: Individual posts (toots)
- **User**: Authentication/login credentials for local accounts
- **ActivityPub**: Federation protocol implementation in `app/lib/activitypub/`
- **Sidekiq Workers**: Background job processing for federation, media processing, etc.

### API Structure

The application provides two main API surfaces:
1. **REST API** (`app/controllers/api/`) - Mastodon API v1 and v2
2. **Streaming API** (`streaming/`) - Real-time WebSocket connections

### Frontend State Management

Uses Redux with the following key stores:
- `compose` - Post composition state
- `timelines` - Timeline data and pagination
- `accounts` - Account information cache
- `statuses` - Status/post cache
- `notifications` - Notification management

## Development Workflow Tips

1. **Feature Development**: Most features touch both backend (Rails) and frontend (React). Start with models/services, then API endpoints, then UI components.

2. **Federation Testing**: Use `bin/rails console` to inspect ActivityPub payloads. Check `app/workers/activitypub/` for federation job processing.

3. **Real-time Features**: Changes to real-time functionality require coordination between Rails (publishing), Streaming server (broadcasting), and React (subscribing).

4. **Database Changes**: Always use Rails migrations (`bin/rails generate migration`). Never modify schema.rb directly.

5. **Asset Pipeline**: Frontend assets are handled by Vite. Configuration in `vite.config.mts`.

## Testing Approach

- **Ruby**: RSpec for unit and integration tests. Run with `bundle exec rspec`
- **JavaScript**: Vitest for unit tests. Run with `yarn test:js`
- **E2E**: Use development instance with test accounts

## Important Configuration Files

- `config/database.yml` - Database configuration
- `config/redis.yml` - Redis configuration  
- `.env.production` - Production environment variables
- `config/settings.yml` - Application settings
- `vite.config.mts` - Vite bundler configuration
- `config/routes.rb` - Rails routing

## Docker Build Requirements

### Platform Support in Gemfile.lock
When updating gems on macOS that have native extensions (like nokogiri, ffi, etc.), you MUST add Linux platform support to Gemfile.lock before Docker builds will work:

```bash
# Run this command to add Linux x86_64 platform support:
docker run --rm -v $(pwd):/app -w /app ruby:3.4.4-slim-bookworm sh -c \
  "apt-get update && apt-get install -y git && bundle lock --add-platform x86_64-linux"

# Then commit the changes:
git add Gemfile.lock
git commit -m "Add Linux platform for Docker builds"
```

Without this, Docker builds will fail with errors like "Could not find [gem_name] in locally installed gems" during the bootsnap precompile step.

## Common Tasks

### Creating a new API endpoint
1. Add route in `config/routes.rb`
2. Create controller in `app/controllers/api/`
3. Add serializer in `app/serializers/`
4. Write tests in `spec/controllers/`

### Adding a new React component
1. Create component in `app/javascript/mastodon/components/` or `features/`
2. Add Redux actions/reducers if needed
3. Connect to API via action creators
4. Add translations to locale files

### Modifying the database schema
1. Generate migration: `bin/rails generate migration AddFieldToModel`
2. Edit migration file in `db/migrate/`
3. Run migration: `bin/rails db:migrate`
4. Update model validations and tests