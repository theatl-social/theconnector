# CDN_HOST Debugging Notes

## Issue Summary

The "Validate CDN Asset Manifest" CI test is failing because assets in the Vite manifest.json file don't have the CDN_HOST prefix, even though CDN_HOST is set in the environment during build.

**Expected**: `https://cdn-test.example.com/packs/intl/af-intl-pluralrules-BF83YLYX.js`
**Actual**: `intl/af-intl-pluralrules-BF83YLYX.js`

## Implementation Approach

We're implementing a build-time CDN_HOST solution using Vite's `base` configuration option:

```typescript
// vite.config.mts lines 42-60
const cdnHost = process.env.CDN_HOST;
const isProdBuild = mode === 'production' && command === 'build';

const base =
  isProdBuild && cdnHost ? `${cdnHost}/${outDirName}/` : `/${outDirName}/`;

return {
  root: jsRoot,
  base, // This should make Vite prepend base to all asset URLs
  // ...
};
```

## What We Know

1. **Environment variable IS set**: CI logs show `CDN_HOST: https://cdn-test.example.com`
2. **Build completes successfully**: No errors during `yarn build:production`
3. **Assets are generated**: Files appear in `public/packs/`
4. **But**: Assets don't have CDN prefix in manifest.json

## Possible Causes

### Theory 1: `mode` or `command` incorrect

- `isProdBuild` condition might not evaluate to true
- Vite's `mode` parameter might not be 'production'
- Added debug logging to verify (commit 1b224bf)

### Theory 2: Vite not respecting `base`

- Something in v4.5.0 might override or ignore `base`
- Need to check if there are other plugins modifying manifest

### Theory 3: `envDir` configuration issue

- `envDir: __dirname` points to project root
- Maybe Vite isn't reading process.env correctly?

### Theory 4: Timing issue

- Config is exported as async function
- Maybe CDN_HOST check happens before env is loaded?

## Debug Logging Added

Added console.log statements in vite.config.mts (lines 47-60) to output:

- `mode` value
- `command` value
- `isProdBuild` result
- `process.env.CDN_HOST` value
- `cdnHost` variable value
- `outDirName` value
- Final `base` value

This should appear in CI build output.

## Historical Context

From conversation summary:

- User mentioned: "something changed between PR 10 and the v.4.5.0 release that created this regression for CDN_HOST"
- PR #12 attempted to fix this but was reverted
- v4.5.0 tag uses **runtime** CDN_HOST via Rails config.asset_host
- This PR implements **build-time** CDN_HOST via Vite base config

## Key Question

**Is build-time CDN_HOST the right approach for v4.5.0?**

The user asked about "runtime (not buildtime) CDN_HOST functionality" being maintained in v4.5.0. The answer was yes - v4.5.0 uses Rails `config.asset_host` which is runtime.

But we're implementing a **build-time** solution (Vite base config). This means:

- CDN URL must be known at Docker build time
- Can't change CDN without rebuilding image
- Different from how v4.5.0 originally worked

**Need to verify**: Does v4.5.0 actually have a CDN_HOST problem, or does it work fine with runtime config.asset_host?

## Files Modified

1. `vite.config.mts` - Added CDN_HOST logic and debug logging
2. `Dockerfile` - Added CDN_HOST build arg
3. `.github/workflows/build-container-image.yml` - Added cdn_host input
4. `.github/workflows/test-cdn-assets.yml` - Created test workflow
5. `spec/system/cdn_assets_spec.rb` - Created RSpec tests

## Next Steps

1. Wait for CI to run with debug logging
2. Analyze debug output to see what values Vite receives
3. Determine if approach is fundamentally correct
4. May need to switch to runtime approach if build-time doesn't work

## Commands for Local Testing

```bash
# Set CDN_HOST and build locally
CDN_HOST=https://cdn-test.example.com yarn build:production

# Check manifest for CDN URLs
cat public/packs/.vite/manifest.json | grep "https://cdn-test"

# Should see URLs like: "file": "https://cdn-test.example.com/packs/..."
```

## Rubocop Fixes Applied

Fixed linting errors in `spec/system/cdn_assets_spec.rb` (commit f3f14d5):

- Replaced `.nil? || .empty?` with `.blank?`
- Added `.to_a` before `.each` to avoid Rails/FindEach warnings on Capybara collections

## Current Status

Waiting for CI run #19343912767 to complete to see debug logging output.
