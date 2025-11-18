# TheConnector Upstream Merge Procedure

This document describes the complete process for merging new commits from upstream Mastodon into TheConnector's `forked-main` branch.

## Overview

TheConnector is a fork of Mastodon with customizations. We regularly merge upstream changes to stay current with Mastodon development while preserving our custom features.

**Branch Strategy:**

- `main` - Tracks upstream Mastodon (do not use for our changes)
- `forked-main` - TheConnector's main branch with customizations
- `merge-v4.x.x-YYYYMMDD` - Temporary branches for merging upstream changes
- `upstream` - Remote pointing to https://github.com/mastodon/mastodon

## Prerequisites

### Required Tools

- Git configured with upstream remote
- Ruby 3.4.6+ (via Homebrew, rbenv, or ruby-install/chruby)
- Node.js 24+
- Docker (for platform-specific builds)
- GitHub CLI (`gh`)
- Bundle and Yarn

### Upstream Remote Setup

```bash
# Add upstream remote if not already configured
git remote add upstream https://github.com/mastodon/mastodon.git

# Verify remotes
git remote -v
```

## Step-by-Step Merge Procedure

### 1. Find Latest Passing Upstream Commit

Identify the most recent upstream commit where all CI checks passed:

```bash
# Fetch latest upstream
git fetch upstream main

# View recent commits
git log --oneline HEAD..upstream/main | head -20

# Check CI status for a specific commit (replace COMMIT_SHA)
gh api repos/mastodon/mastodon/commits/COMMIT_SHA/check-runs \
  --jq '[.check_runs[] | select(.status == "completed")] | group_by(.conclusion) | map({conclusion: .[0].conclusion, count: length}) | .[]'
```

**Success criteria:** All checks show `{"conclusion":"success","count":30}` (or similar high count with no failures)

**Good merge points:**

- Version tag commits (e.g., v4.5.0-rc.1, v4.6.0-alpha.1)
- Commits with all green checks
- After major feature merges

### 2. Create Merge Branch

```bash
# Ensure you're on forked-main and up to date
git checkout forked-main
git pull origin forked-main

# Create dated merge branch (use YYYYMMDD format)
git checkout -b merge-v4.x.x-YYYYMMDD forked-main
```

**Branch naming convention:** `merge-v4.x.x-YYYYMMDD`

- Use the Mastodon version being merged (e.g., v4.6.x)
- Use the date you're creating the branch
- Example: `merge-v4.6.x-20251111`

### 3. Merge Upstream Commits

```bash
# Merge to the specific commit you identified
git merge COMMIT_SHA --no-edit
```

This will likely produce merge conflicts. **This is expected and normal.**

### 4. Resolve Merge Conflicts

#### Auto-Resolve Locale Files

Locale files always conflict due to TheConnector customizations. **Always keep ours:**

```bash
git checkout --ours config/locales/*.yml
git checkout --ours app/javascript/mastodon/locales/*.json
git add config/locales/*.yml app/javascript/mastodon/locales/*.json
```

#### Resolve Lockfiles

Take upstream versions and regenerate:

```bash
# Take upstream Gemfile.lock and yarn.lock
git checkout --theirs Gemfile.lock yarn.lock
git add Gemfile.lock yarn.lock
```

#### Resolve Workflow Files

If `.github/workflows/` files conflict:

```bash
# Usually safe to take upstream
git checkout --theirs .github/workflows/build-releases.yml
git add .github/workflows/build-releases.yml
```

#### Check for Remaining Conflicts

```bash
git status --short | grep "^UU"
```

If other files have conflicts, review them carefully to preserve TheConnector customizations:

- ENV var patterns (STATUS_LENGTH_CHARS_LIMIT, NOTE_LENGTH_LIMIT, throttle settings)
- Custom features
- Configuration overrides

### 5. Update Version String

Edit `lib/mastodon/version.rb`:

```ruby
def patch
  '0-theatlsocial-nightly-YYYYMMDD'
end

def default_prerelease
  '' # Empty string for nightly builds, or keep upstream value for rc/alpha releases
end
```

**Version format:** `4.x.0-theatlsocial-nightly-YYYYMMDD`

```bash
git add lib/mastodon/version.rb
```

### 6. Add Linux Platform to Gemfile.lock

Docker builds require Linux platform support in Gemfile.lock:

```bash
docker run --rm -v $(pwd):/app -w /app ruby:3.4.6-slim-bookworm sh -c \
  "apt-get update -qq && apt-get install -y -qq git && bundle lock --add-platform x86_64-linux"
```

This ensures Docker builds don't fail with "Could not find gem in locally installed gems."

### 7. Regenerate yarn.lock

Must be done in a Linux x86_64 environment to match CI:

```bash
docker run --rm -v $(pwd):/app -w /app node:24.10.0-bookworm bash -c \
  "corepack enable && yarn install"
```

**Why?** CI runs `yarn install --immutable` which fails if the lockfile was generated on a different architecture.

### 8. Stage and Commit

```bash
git add Gemfile.lock yarn.lock
```

Count the commits being merged:

```bash
git log --oneline HEAD..COMMIT_SHA | wc -l
```

Create commit message:

```bash
git commit --no-verify -m "Update version to X.X.X-theatlsocial-nightly-YYYYMMDD

Merge upstream Mastodon main branch (N new commits) up to COMMIT_SHA:

Key changes:
- [List major changes, version bumps, important features]
- [Include PR numbers from upstream]

Full upstream commits: PREVIOUS_SHA..COMMIT_SHA

Resolved conflicts:
- Locale files: kept ours (TheConnector customizations)
- Gemfile.lock: took upstream, added x86_64-linux platform for Docker
- yarn.lock: regenerated in linux/x86_64 container
- lib/mastodon/version.rb: updated to nightly-YYYYMMDD

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

**Note:** Use `--no-verify` to skip pre-commit hooks for large merges.

### 9. Push and Create Pull Request

```bash
# Temporarily switch to HTTPS for push (if SSH keys aren't configured)
git remote set-url origin https://github.com/theatl-social/theconnector.git
git push -u origin merge-v4.x.x-YYYYMMDD

# Restore SSH URL
git remote set-url origin git@github.com:theatl-social/theconnector.git

# Create PR
gh pr create --base forked-main --head merge-v4.x.x-YYYYMMDD \
  --title "Merge Mastodon vX.X.X-xxx (YYYYMMDD) into TheConnector" \
  --body "See commit message for details

## Summary
[Brief summary of what's being merged]

## Key Changes
[Bulleted list of important changes]

## Merge Details
- Upstream commits: PREVIOUS_SHA..COMMIT_SHA (N commits)
- Target version: X.X.X-theatlsocial-nightly-YYYYMMDD

## Conflict Resolution
[List how conflicts were resolved]

🤖 Generated with [Claude Code](https://claude.com/claude-code)"
```

### 10. Monitor CI/CD

Watch for failures: `https://github.com/theatl-social/theconnector/pull/PR_NUMBER/checks`

**Common CI failures:**

#### yarn.lock mismatch

- **Symptom:** `yarn install --immutable` fails
- **Fix:** Regenerate yarn.lock in Docker (see step 7)

#### RuboCop violations

```bash
bundle exec rubocop --auto-correct
bundle exec rubocop  # Check remaining
```

#### TypeScript/ESLint errors

```bash
yarn lint:js --fix
yarn typecheck
```

#### Test failures

- Check if tests fail on upstream too
- Look for TheConnector-specific customizations that need updating
- Review breaking changes in the commits being merged

### 11. Merge to forked-main

Once all checks pass:

```bash
gh pr merge PR_NUMBER --merge
```

This triggers private Docker build workflows on `forked-main` that build and tag images.

## Key Files and Customizations

### Always Preserve Our Changes In:

1. **config/initializers/rack_attack.rb**
   - ENV var patterns for rate limiting
   - Custom throttle configurations

2. **app/validators/status_length_validator.rb**
   - ENV var for `STATUS_LENGTH_CHARS_LIMIT`

3. **app/models/account.rb**
   - ENV var for `NOTE_LENGTH_LIMIT` (bio length)

4. **lib/mastodon/version.rb**
   - Custom version format: `X.X.0-theatlsocial-nightly-YYYYMMDD`

5. **Locale files** (all)
   - Always keep ours to preserve custom translations

### Files to Take Upstream:

1. **Gemfile.lock** (with platform addition)
2. **yarn.lock** (regenerated)
3. **.github/workflows/** (usually)
4. **Dockerfile** (usually, check for custom changes)
5. **docker-compose.yml** (usually)

## Troubleshooting

### Docker Build Failures

**"Could not find gem_name in locally installed gems"**

- Missing Linux platform in Gemfile.lock
- Run platform addition command (step 6)

**"SecretsUsedInArgOrEnv warnings"**

- Check Dockerfile uses BuildKit secret mounts
- Secrets should only appear in precompiler stage
- Already configured correctly in our Dockerfile

### Merge Conflicts in Critical Files

1. Open the file and look for `<<<<<<< HEAD` markers
2. Review both sides of the conflict
3. Manually merge to preserve:
   - All `ENV['VARIABLE']` patterns
   - TheConnector-specific features
   - Custom configurations
4. Test that functionality still works

### CI/CD Transient Failures

Some tests occasionally fail due to infrastructure issues:

- **End-to-End tests** - Database initialization timing
- **ElasticSearch tests** - Service startup timing

**Symptoms:**

- Only one Ruby version fails
- Error mentions "role 'root' does not exist" or connection refused
- Other similar tests pass

**Solution:** Re-run failed jobs via GitHub UI or:

```bash
gh run rerun RUN_ID --failed
```

## Docker Build Process

### Private Workflows

After merging to `forked-main`, these workflows automatically build Docker images:

1. **private-build-compiled-mastodon.yml** - Main Rails application
2. **private-streaming-compiled.yml** - Streaming server

### Automatic Image Tagging

Images are tagged as: `YYYYMMDD-{short-hash}`

- Example: `20251111-abc1234`
- Manual workflow_dispatch available for custom tags

### Build Secrets

Main Dockerfile uses BuildKit secret mounts (streaming doesn't need secrets):

- Secrets passed to precompiler stage only
- Never persist in final image layers
- Uses real secrets for proper asset compilation

## Version Numbering

### Format

**TheConnector:** `4.X.0-theatlsocial-nightly-YYYYMMDD`
**Upstream:** `4.X.0-alpha.N` or `4.X.0-rc.N`

### Components

```ruby
def major; 4; end
def minor; X; end  # Matches upstream minor version
def patch; '0-theatlsocial-nightly-YYYYMMDD'; end
def default_prerelease; ''; end  # Empty for nightly, or keep upstream alpha/rc
```

### When to Update

- **minor**: When upstream bumps minor (4.5 → 4.6)
- **patch**: Every merge (update date)
- **prerelease**: Usually empty string, or keep upstream's alpha/rc designation

## Testing Before Production

### Local Testing

```bash
# Run RuboCop
bundle exec rubocop

# Run RSpec
bundle exec rspec spec/

# Run JS tests
yarn test:js
yarn lint
yarn typecheck
```

### Development Instance Testing

- Deploy to development environment
- Test key TheConnector features
- Verify customizations still work
- Check ENV var configurations

## Best Practices

### Merge Frequency

- **Recommended:** Weekly or bi-weekly
- **Minimum:** Monthly to avoid large, difficult merges
- **After major releases:** Merge soon after upstream releases rc or stable versions

### Commit Selection

- ✅ **Good:** Version tag commits (v4.X.0-rc.1)
- ✅ **Good:** After feature freeze before release
- ✅ **Good:** All checks passing
- ❌ **Avoid:** Mid-feature commits
- ❌ **Avoid:** Commits with failing checks
- ❌ **Avoid:** During active upstream refactoring

### Documentation

- Keep this file updated with new patterns
- Document any new TheConnector customizations
- Note breaking changes from upstream
- Record solutions to new types of conflicts

## Getting Help

### Resources

- **Upstream Mastodon:** https://github.com/mastodon/mastodon
- **TheConnector Issues:** https://github.com/theatl-social/theconnector/issues
- **Mastodon Docs:** https://docs.joinmastodon.org/dev/
- **Docker BuildKit:** https://docs.docker.com/build/building/secrets/

### Common Commands Reference

```bash
# Check upstream commits
git log --oneline upstream/main | head -20

# Check PR status
gh pr checks PR_NUMBER

# View CI logs
gh run view RUN_ID --log-failed

# Re-run failed jobs
gh run rerun RUN_ID --failed

# Merge PR
gh pr merge PR_NUMBER --merge
```

## Checklist Template

Use this checklist when performing a merge:

- [ ] Fetch latest upstream: `git fetch upstream main`
- [ ] Find passing commit (all checks green)
- [ ] Update forked-main: `git checkout forked-main && git pull`
- [ ] Create merge branch: `git checkout -b merge-v4.x.x-YYYYMMDD`
- [ ] Merge upstream commit: `git merge COMMIT_SHA --no-edit`
- [ ] Resolve locale conflicts: Keep ours
- [ ] Resolve lockfile conflicts: Take theirs
- [ ] Update version in lib/mastodon/version.rb
- [ ] Add Linux platform to Gemfile.lock (Docker)
- [ ] Regenerate yarn.lock in Docker
- [ ] Stage all changes
- [ ] Commit with descriptive message
- [ ] Push branch
- [ ] Create PR with detailed description
- [ ] Monitor CI/CD checks
- [ ] Address any failures
- [ ] Merge to forked-main when green
- [ ] Verify Docker builds succeed
- [ ] Test in development environment

---

**Last Updated:** 2024-10-29
**Maintainer:** TheConnector Team
