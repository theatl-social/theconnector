# TheConnector Fork Merge Procedure

This document outlines the process for merging upstream Mastodon nightly builds into TheConnector fork.

## Prerequisites

- Access to the `theconnector` repository
- `upstream` remote configured to point to `https://github.com/mastodon/mastodon`
- Ruby 3.4.6+ installed (via Homebrew's ruby-install/chruby or rbenv)
- Node.js 22+ installed
- Bundle and Yarn dependencies installed

## Daily Merge Procedure

### 1. Create New Merge Branch

Create a new dated branch from `forked-main`:

```bash
git checkout forked-main
git pull origin forked-main
git checkout -b merge-v4.5.x-YYYYMMDD forked-main
```

Example: `merge-v4.5.x-20250930`

### 2. Fetch and Merge Upstream

Fetch the latest upstream changes and merge:

```bash
git fetch upstream main
git log --oneline HEAD..upstream/main | head -20  # Preview changes
git merge upstream/main --no-edit
```

### 3. Resolve Merge Conflicts

If conflicts occur:

#### Auto-resolve locale files (if needed)
```bash
# Take ours for locale files
git checkout --ours config/locales/*.yml
git add config/locales/*.yml
```

#### Manually review critical files
Pay special attention to:
- **ENV var customizations**: Preserve `ENV['STATUS_LENGTH_CHARS_LIMIT']`, `ENV['NOTE_LENGTH_LIMIT']`, and throttle settings
- **config/initializers/rack_attack.rb**: Keep ENV var patterns for rate limiting
- **app/validators/status_length_validator.rb**: Keep ENV var for character limits
- **app/models/account.rb**: Keep ENV var for bio length

#### Check for duplicate code from merge
Common issues:
- Duplicate method definitions
- Duplicate RSpec describe/context blocks
- Duplicate constants

### 4. Update Version String

Edit `lib/mastodon/version.rb`:

```ruby
def patch
  '0-theatlsocial-nightly-YYYYMMDD'
end
```

Commit the version update:

```bash
git add lib/mastodon/version.rb
git commit -m "Update version to 4.5.0-theatlsocial-nightly-YYYYMMDD

Merge upstream Mastodon main branch (X new commits):
- commit1 description
- commit2 description

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

### 5. Push and Create PR

```bash
git push -u origin merge-v4.5.x-YYYYMMDD
gh pr create --base forked-main --head merge-v4.5.x-YYYYMMDD \
  --title "Merge Mastodon v4.5.0-alpha.2 nightly (YYYYMMDD) into TheConnector" \
  --body "See commit message for details"
```

### 6. Fix CI/CD Issues

Monitor the PR and fix any CI/CD failures:

#### Common Issues

**RuboCop failures:**
```bash
bundle exec rubocop --auto-correct  # Auto-fix safe issues
bundle exec rubocop                  # Check remaining issues
```

**Duplicate code:**
- Check for duplicate methods, constants, or RSpec blocks
- Remove duplicates introduced by merge conflicts

**Missing translations:**
- Add missing translation keys (e.g., `notification_mailer.quote`)
- Check `config/locales/en.yml`

**TypeScript/ESLint errors:**
```bash
yarn lint:js --fix
yarn typecheck
```

### 7. Create Fix Branch (if needed)

If CI/CD fails, create a fix branch:

```bash
git checkout -b fix-cicd-builds merge-v4.5.x-YYYYMMDD
# Make fixes
git add <files>
git commit -m "Fix CI/CD: <description>"
git push -u origin fix-cicd-builds
gh pr create --base merge-v4.5.x-YYYYMMDD --head fix-cicd-builds
```

After PR is merged, continue with main merge PR.

### 8. Merge to forked-main

Once all checks pass:

```bash
gh pr merge <PR_NUMBER> --merge
```

This triggers the private Docker build workflows on `forked-main`.

## Docker Build Configuration

### Private Workflows

Two private workflows build Docker images on push to `forked-main`:

1. **private-build-compiled-mastodon.yml** - Main Rails application
2. **private-streaming-compiled.yml** - Streaming server

### Automatic Tagging

Images are automatically tagged with `YYYYMMDD-{short-hash}` format:
- Example: `20250930-abc1234`
- Manual workflow_dispatch allows custom version tags

### Secrets for Asset Precompilation

The main Dockerfile uses BuildKit secret mounts for asset precompilation:
- Secrets passed via workflow to precompiler stage only
- Secrets do NOT persist in final image layers
- Uses real secrets (not dummy) for proper asset compilation

**Required secrets:**
- `ARG_SECRET_KEY_BASE`
- `ARG_OTP_SECRET`
- `ARG_VAPID_PRIVATE_KEY`
- `ARG_VAPID_PUBLIC_KEY`
- `ARG_ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY`
- `ARG_ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT`
- `ARG_ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY`

**Note:** Streaming Dockerfile does NOT need secrets (Node.js only)

## Testing Locally Before Pushing

### Run RuboCop
```bash
bundle exec rubocop <changed-files>
```

### Run RSpec Tests
```bash
bundle exec rspec spec/
```

### Run JavaScript Tests
```bash
yarn test:js
yarn lint
yarn typecheck
```

## Troubleshooting

### Docker Build Failures

**Missing Linux platform in Gemfile.lock:**
```bash
docker run --rm -v $(pwd):/app -w /app ruby:3.4.6-slim-bookworm sh -c \
  "apt-get update && apt-get install -y git && bundle lock --add-platform x86_64-linux"
git add Gemfile.lock
git commit -m "Add Linux platform for Docker builds"
```

**SecretsUsedInArgOrEnv warnings:**
- Ensure secrets use BuildKit secret mounts (`--mount=type=secret`)
- Do NOT use ARG/ENV for secrets in Dockerfile
- Secrets should only be in precompiler stage RUN command

### Merge Conflicts

**Preserve TheConnector customizations:**
1. Check git diff for ENV var usage
2. Manually merge to keep ENV patterns
3. Test that customizations still work

**Common conflict files:**
- `config/initializers/rack_attack.rb`
- `app/validators/status_length_validator.rb`
- `app/models/account.rb`
- `lib/mastodon/version.rb`

## Key Customizations to Preserve

### Character Limits (ENV-based)
- `STATUS_LENGTH_CHARS_LIMIT` - Post character limit
- `NOTE_LENGTH_LIMIT` - Bio character limit

### Rate Limiting (ENV-based)
All throttle limits in `rack_attack.rb`:
- `THROTTLE_AUTHENTICATED_API_LIMIT`
- `THROTTLE_AUTHENTICATED_API_PERIOD_MINUTES`
- And others...

### Version Format
Always use: `X.X.X-theatlsocial-nightly-YYYYMMDD`

## Workflow Files

### Main Workflows (from upstream)
Synchronized with upstream Mastodon:
- `.github/workflows/test-ruby.yml`
- `.github/workflows/test-js.yml`
- `.github/workflows/lint-*.yml`
- etc.

### Private Workflows (TheConnector-specific)
**DO NOT sync with upstream:**
- `.github/workflows/private-build-compiled-mastodon.yml`
- `.github/workflows/private-streaming-compiled.yml`

## Branch Strategy

- `main` - **DO NOT USE** (reserved for upstream tracking)
- `forked-main` - TheConnector's main branch for deployments
- `merge-v4.5.x-YYYYMMDD` - Daily merge branches
- `fix-cicd-builds` - Temporary fix branches as needed
- `dev/**` - Development branches
- `prod/**` - Production branches

## References

- Upstream Mastodon: https://github.com/mastodon/mastodon
- TheConnector Issues: https://github.com/theatl-social/theconnector/issues
- Docker BuildKit Secrets: https://docs.docker.com/build/building/secrets/
