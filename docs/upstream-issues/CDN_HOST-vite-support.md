# Upstream Issue: CDN_HOST Support for Vite Assets

**Status:** Draft - Ready to file
**Target:** mastodon/mastodon repository
**Labels:** `bug`, `enhancement`, `deployment`, `docker`

---

## Issue Title

CDN_HOST environment variable not respected for Vite-generated assets

## Description

After the migration from Webpack to Vite in v4.4.0 (PR #34450), the `CDN_HOST` environment variable is no longer fully respected for all Vite-generated assets. This causes JavaScript chunks, emoji data files, and other dynamically loaded assets to be fetched from the local domain instead of the configured CDN, breaking deployments that rely on CDN asset serving.

## Environment

- **Mastodon version:** 4.4.0+ (any version using Vite)
- **Deployment method:** Docker, bare metal (any)
- **Configuration:** `CDN_HOST` set in production environment
- **Impact:** All production deployments using CDN for assets

## Steps to Reproduce

1. Set `CDN_HOST=https://cdn.example.com` in your production environment
2. Build and deploy Mastodon
3. Load the web interface in a browser
4. Open browser DevTools → Network tab
5. Observe asset requests

## Expected Behavior

**With Webpack (v4.3.x and earlier):**

All assets should be loaded from the CDN:
- ✅ `https://cdn.example.com/packs/application-abc123.js`
- ✅ `https://cdn.example.com/packs/features_ui-xyz789.js` (code-split chunks)
- ✅ `https://cdn.example.com/packs/emoji/en.json`
- ✅ `https://cdn.example.com/packs/intl/en-abc123.js` (locale files)

## Actual Behavior

**With Vite (v4.4.0+):**

Only initial HTML-embedded assets use CDN, dynamic assets do not:
- ✅ `https://cdn.example.com/packs/application-abc123.js` (works - via vite_javascript_tag)
- ❌ `https://mastodon.example.com/packs/features_ui-xyz789.js` (broken - dynamic import)
- ❌ `https://mastodon.example.com/packs/emoji/en.json` (broken - fetch in loader.ts)
- ❌ `https://mastodon.example.com/packs/intl/en-abc123.js` (broken - import.meta.glob)

## Impact

This issue causes:
- **Increased load on application servers** - defeats the purpose of using a CDN
- **Potential CORS errors** if headers not configured
- **Performance degradation** for users far from application server
- **Broken deployments** for instances that require CDN usage
- **Subresource Integrity failures** in some cases

This affects **any** Mastodon instance using:
- CDN for asset delivery (CloudFront, Cloudflare, Fastly, etc.)
- Multi-server deployments with separate asset server
- Geographically distributed deployments
- Shared hosting with asset optimization
- Dockerized deployments using pre-built images

## Root Cause Analysis

### Why This Worked with Webpack

Webpack supported `__webpack_public_path__` which could be set at runtime:

```javascript
__webpack_public_path__ = window.cdnHost + '/packs/';
```

All dynamic imports and code-split chunks respected this value.

### Why This Breaks with Vite

Vite's `base` configuration option is build-time only:

```typescript
// vite.config.mts
export default {
  base: '/packs/', // This is BAKED IN at build time
}
```

When Vite processes:
- `import('./features/ui')` → generates `/packs/features_ui-hash.js`
- `import.meta.glob('./*.json')` → generates object with `/packs/` paths
- Code splitting → manifest entries have `/packs/` paths

These paths are generated during `vite build` and **cannot be changed at runtime**.

### Rails Integration Gap

While Rails' `config.asset_host` works for vite_rails helper tags:

```haml
= vite_javascript_tag 'application'
# Generates: <script src="https://cdn.example.com/packs/application-hash.js">
```

It does NOT affect:
- JavaScript `import()` statements
- `import.meta.glob()` results
- Vite's internal manifest URLs
- Manually constructed URLs in JavaScript

## Proposed Solutions

### Option 1: Build-Time CDN_HOST (Recommended)

**Change:** Make Vite's `base` option use `CDN_HOST` during build.

**Implementation:**

```typescript
// vite.config.mts
const cdnHost = process.env.CDN_HOST;
const isProdBuild = mode === 'production' && command === 'build';
const base = isProdBuild && cdnHost
  ? `${cdnHost}/${outDirName}/`
  : `/${outDirName}/`;

export default {
  base,
  // ... rest of config
}
```

**Dockerfile change:**
```dockerfile
ARG CDN_HOST=""
ENV CDN_HOST=${CDN_HOST}
RUN bundle exec rails assets:precompile
```

**Pros:**
- ✅ Simple, 5-line change to vite.config.mts
- ✅ Works with ALL assets (100% coverage)
- ✅ No runtime overhead
- ✅ No new dependencies
- ✅ Proven approach (used by many Vite apps)
- ✅ Standard practice in Vite ecosystem

**Cons:**
- ❌ Requires CDN_HOST at build time
- ❌ Docker image "locked" to specific CDN
- ❌ Can't change CDN without rebuild

**Best for:** Most deployments, official Docker images with build args

### Option 2: Runtime CDN_HOST (More Flexible)

**Change:** Use Vite plugin for runtime public path configuration.

**Implementation:**
1. Add `vite-plugin-dynamic-publicpath` dependency
2. Configure plugin in vite.config.mts
3. Inject runtime handler reading `<meta name="cdn-host">` tag
4. Fix manual URL construction in loader.ts

**Pros:**
- ✅ Single Docker image for any CDN
- ✅ Change CDN without rebuild
- ✅ Most flexible for forks/instances

**Cons:**
- ⚠️ Adds dependency
- ⚠️ More complex implementation
- ⚠️ Small runtime overhead
- ⚠️ Requires thorough testing

**Best for:** Multi-tenant deployments, maximum flexibility

### Option 3: Hybrid Approach

**Change:** Combine both approaches.

- Use build-time CDN_HOST if available (Option 1)
- Fall back to runtime detection if not set (Option 2)

**Pros:**
- ✅ Works for both scenarios
- ✅ Backwards compatible

**Cons:**
- ⚠️ Most complex
- ⚠️ Hardest to maintain

## Recommendation

I recommend **Option 1 (Build-Time CDN_HOST)** because:

1. **Simplicity:** Minimal code change, easy to review/test
2. **Reliability:** No runtime logic, no edge cases
3. **Performance:** Zero overhead, all URLs resolved at build time
4. **Standard practice:** How most Vite applications handle CDN
5. **Backward compatible:** Defaults to current behavior if CDN_HOST not set

The build-time approach aligns with how Docker images work - they're immutable artifacts configured at build time. Instances that need different CDNs can build their own images with appropriate CDN_HOST (same as they do for other build-time configuration like version numbers and branding).

## Implementation Details

### Files to Modify

1. **vite.config.mts** (5 lines added)
   - Add CDN_HOST logic to base path calculation

2. **Dockerfile** (3 lines added)
   - Add CDN_HOST build arg declaration
   - Pass to asset precompilation step

3. **.env.production.sample** (1 line added)
   - Document CDN_HOST variable

4. **docs/Running-Mastodon/Docker-Guide.md** (section added)
   - Document build arg usage

### Example Usage

**Docker build:**
```bash
# Without CDN (default)
docker build -t mastodon:latest .

# With CDN
docker build --build-arg CDN_HOST=https://cdn.example.com -t mastodon:latest .
```

**docker-compose:**
```yaml
services:
  web:
    build:
      args:
        CDN_HOST: ${CDN_HOST:-}
```

**GitHub Actions:**
```yaml
- uses: docker/build-push-action@v6
  with:
    build-args: |
      CDN_HOST=${{ vars.CDN_HOST }}
```

## Testing Strategy

Comprehensive test coverage included in implementation:

### Stage 1: Static Manifest Analysis (Fast - 2 min)
- Build with test CDN_HOST
- Parse manifest.json
- Verify all entries use CDN_HOST
- Check emoji files exist
- Scan for hardcoded paths

### Stage 2: Integration Tests (Medium - 10 min)
- Start Rails server with CDN_HOST
- Fetch rendered HTML
- Parse all asset tags
- Verify CDN_HOST prefix
- Test multiple pages

Tests prevent future regressions and ensure feature works correctly.

## Backwards Compatibility

The proposed change is **fully backward compatible**:

- ✅ If `CDN_HOST` not set → behaves exactly as current (base = '/packs/')
- ✅ If `CDN_HOST` set → uses CDN for all assets
- ✅ No breaking changes to existing deployments
- ✅ No changes to Rails configuration required
- ✅ No API changes

## Migration Path

For instances currently using workarounds:

**Before:** Build custom image with modified vite.config.mts
```bash
# Manual fork with changes
```

**After:** Use official image with build arg
```bash
docker build --build-arg CDN_HOST=https://cdn.example.com -t mastodon .
```

Or set `CDN_HOST` in environment before build, or continue using runtime `config.asset_host` for HTML-only assets (still works for initial page load).

## Related Issues

- #35461 - WebUI blank when assets CDN is enabled (CORS/Workers issue)
- #34450 - Convert from Webpack to Vite (original migration)
- (Historical) #14381 - CDN_HOST not being reproducible

## References

### Similar Implementations

Other Rails + Vite projects handle CDN configuration similarly:

- **Shopify/vite_ruby:** Documents using `ASSET_HOST` env var in deployment guides
- **Various React+Vite apps:** Use build-time `base` config with environment variables
- **Discourse:** Uses Ember CLI with build-time CDN configuration

### Vite Documentation

- [Base Path Configuration](https://vitejs.dev/config/shared-options.html#base)
- [Build Options](https://vitejs.dev/config/build-options.html)
- [Environment Variables](https://vitejs.dev/guide/env-and-mode.html)

## Offer to Implement

I'm happy to:
- 📝 Submit a PR implementing Option 1 (Build-Time CDN_HOST)
- 🧪 Write comprehensive tests (both stages)
- 📖 Update documentation (Docker guide, deployment guide)
- 💬 Discuss alternative approaches
- 🐛 Fix any issues that arise

**Implementation status:** Already tested in fork with positive results. Can provide:
- Network traces showing CDN usage
- Performance comparisons (before/after)
- Working branch for review
- Test results from CI

## Example Results

**Before (v4.5.0 without fix):**
```
GET https://mastodon.example.com/packs/features_ui-abc123.js
```

**After (with CDN_HOST fix):**
```
GET https://cdn.example.com/packs/features_ui-abc123.js
```

**Manifest comparison:**
```json
// Before
{
  "application.ts": {
    "file": "/packs/application-abc123.js"
  }
}

// After
{
  "application.ts": {
    "file": "https://cdn.example.com/packs/application-abc123.js"
  }
}
```

## Community Impact

This issue affects a significant portion of production Mastodon instances:

- **Large instances** (>10k users) commonly use CDN for performance
- **Multi-region deployments** require CDN for global coverage
- **Hosted Mastodon services** need flexible CDN configuration
- **Corporate deployments** often have CDN requirements
- **Cost-conscious admins** use CDN to reduce bandwidth costs

Fixing this would:
- ✅ Restore functionality that existed with Webpack
- ✅ Improve deployment flexibility
- ✅ Enable better performance optimization
- ✅ Reduce operational costs for instances
- ✅ Support professional/enterprise deployments

---

## Notes for Filing

When filing this issue upstream:

1. **Be respectful:** Vite migration was major work by maintainers
2. **Emphasize regression:** This worked with Webpack
3. **Show community impact:** Many instances affected
4. **Offer to help:** PR ready, tests written, willing to maintain
5. **Be patient:** May need discussion and iteration
6. **Provide data:** Network traces, performance metrics, etc.

**Tone:** Collaborative, solution-oriented, appreciative of maintainers' work.
