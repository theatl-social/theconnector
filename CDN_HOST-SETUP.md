# CDN_HOST Setup Guide

This guide explains how to configure CDN_HOST for serving Mastodon assets from a Content Delivery Network (CDN).

## Overview

CDN_HOST allows all Vite-generated static assets (JavaScript bundles, CSS files, images, fonts, etc.) to be served from a CDN instead of your application server. This improves:

- **Performance**: Assets served from geographically distributed CDN edge servers
- **Scalability**: Reduces load on your application servers
- **Cost**: CDN bandwidth often cheaper than direct server bandwidth
- **Reliability**: CDN provides redundancy and DDoS protection

## Requirements

- CDN service (CloudFront, Cloudflare, Fastly, etc.)
- CDN configured to proxy/cache your application's `/packs/` directory
- CORS headers configured if serving from different origin

## Configuration Methods

### Method 1: Docker Build Argument (Recommended)

Set CDN_HOST when building your Docker image:

```bash
docker build \
  --build-arg CDN_HOST=https://cdn.example.com \
  -t mastodon:latest \
  .
```

### Method 2: docker-compose

```yaml
version: '3'
services:
  web:
    build:
      context: .
      dockerfile: Dockerfile
      args:
        CDN_HOST: ${CDN_HOST:-}
    # ... rest of configuration
```

Then set in `.env`:

```bash
CDN_HOST=https://cdn.example.com
```

### Method 3: GitHub Actions

The `cdn_host` input is available in the build workflow:

```yaml
jobs:
  build:
    uses: ./.github/workflows/build-container-image.yml
    with:
      cdn_host: https://cdn.example.com
      # ... other inputs
```

Or use repository variables:

```yaml
jobs:
  build:
    uses: ./.github/workflows/build-container-image.yml
    with:
      cdn_host: ${{ vars.CDN_HOST }}
```

## CDN Provider Setup

### CloudFront (AWS)

1. Create CloudFront distribution
2. Set origin to your Mastodon domain
3. Configure origin path: `/`
4. Path pattern: `/packs/*`
5. Cache behavior: Cache based on headers (if using CORS)
6. Enable compression
7. Set CDN_HOST to: `https://d1234567890.cloudfront.net`

**CORS Headers (if needed):**

Configure CloudFront to forward `Origin` header and cache based on it, or configure your application to send appropriate CORS headers.

### Cloudflare

1. Add your domain to Cloudflare
2. Configure page rule for `/packs/*`:
   - Cache Level: Cache Everything
   - Edge Cache TTL: 1 month
3. Set CDN_HOST to: `https://cdn.example.com`

**Note:** If using Cloudflare proxy, you can use your own subdomain.

### Fastly

1. Create Fastly service
2. Set backend to your Mastodon domain
3. Configure VCL to cache `/packs/*` paths
4. Set long TTLs (assets are fingerprinted/hashed)
5. Set CDN_HOST to: `https://example.fastly.net` or custom domain

## Verification

After deploying with CDN_HOST configured:

### 1. Check HTML Source

View page source and verify `<script>` and `<link>` tags use CDN:

```html
<script src="https://cdn.example.com/packs/application-abc123.js"></script>
<link
  href="https://cdn.example.com/packs/application-xyz789.css"
  rel="stylesheet"
/>
```

### 2. Check Browser Network Tab

1. Open browser DevTools → Network tab
2. Load your Mastodon instance
3. Filter by "JS" or "CSS"
4. Verify Domain column shows CDN domain
5. Check all `/packs/` requests go to CDN

### 3. Check Manifest File

SSH into your container and check the manifest:

```bash
cat public/packs/.vite/manifest.json | grep -o 'https://[^"]*' | head -5
```

All URLs should start with your CDN_HOST.

### 4. Test Dynamic Imports

Navigate through your Mastodon instance (different timelines, settings, etc.) and verify in Network tab that dynamically loaded chunks also come from CDN.

## Troubleshooting

### Assets Still Load from Main Domain

**Possible causes:**

1. **CDN_HOST not set during build**
   - Solution: Rebuild with `--build-arg CDN_HOST=...`
   - Verify: Check manifest.json for CDN URLs

2. **Using pre-built image without CDN_HOST**
   - Solution: Build your own image with CDN_HOST
   - CDN_HOST must be set at BUILD time, not runtime

3. **CDN not caching assets**
   - Solution: Check CDN configuration
   - Verify: `curl -I https://cdn.example.com/packs/application-xyz.js`

### CORS Errors

**Error in console:**

```
Access to script at 'https://cdn.example.com/packs/...' from origin 'https://mastodon.example.com' has been blocked by CORS
```

**Solutions:**

1. **Configure CDN to send CORS headers:**

   ```
   Access-Control-Allow-Origin: https://mastodon.example.com
   Access-Control-Allow-Methods: GET, HEAD
   ```

2. **Or configure CDN to forward CORS headers from origin**

3. **Note:** The `crossorigin="anonymous"` attribute is already set in Mastodon's templates

### Subresource Integrity Failures

**Error in console:**

```
Failed to find a valid digest in the 'integrity' attribute
```

**Causes:**

- CDN modifying files (compression, minification)
- CDN not serving exact same content as origin

**Solutions:**

1. Disable CDN auto-minification/optimization
2. Let Vite handle all compression/optimization
3. Configure CDN for passthrough mode

### Service Worker Issues

**Note:** Service workers MUST be served from same origin as the page, NOT from CDN. Mastodon correctly serves `/sw.js` from main domain, not CDN.

If service worker fails to register, check that it's being served from main domain:

```javascript
// Should be same-origin
navigator.serviceWorker.register('/sw.js'); // ✅ Correct
// NOT from CDN:
navigator.serviceWorker.register('https://cdn.example.com/sw.js'); // ❌ Wrong
```

## Performance Testing

### Before and After Comparison

**Before CDN (all from origin):**

```bash
curl -w "@curl-format.txt" -o /dev/null -s https://mastodon.example.com/packs/application-xyz.js
```

**After CDN:**

```bash
curl -w "@curl-format.txt" -o /dev/null -s https://cdn.example.com/packs/application-xyz.js
```

Check:

- `time_total` (should be lower with CDN)
- `X-Cache` header (should be HIT after first request)
- `speed_download` (should be higher)

### WebPageTest

Use [WebPageTest.org](https://www.webpagetest.org/) to compare:

1. Test without CDN_HOST
2. Deploy with CDN_HOST
3. Test again from same location
4. Compare metrics:
   - First Contentful Paint (FCP)
   - Time to Interactive (TTI)
   - Total Blocking Time (TBT)

Expect 20-50% improvement depending on user location vs server location.

## Security Considerations

### 1. HTTPS Only

Always use HTTPS for CDN_HOST:

```bash
# ✅ Correct
CDN_HOST=https://cdn.example.com

# ❌ Wrong (browser will block mixed content)
CDN_HOST=http://cdn.example.com
```

### 2. Subresource Integrity

Mastodon includes SRI hashes for assets. Ensure CDN serves files unmodified, or SRI verification will fail.

### 3. CDN Authentication

If using a CDN with authentication/signatures (e.g., CloudFront signed URLs), ensure public read access for `/packs/*` paths.

## Cost Optimization

### Cache Everything Aggressively

Assets are fingerprinted with content hashes (e.g., `application-abc123.js`). Safe to cache for very long periods:

```
Cache-Control: public, max-age=31536000, immutable
```

### Enable Compression

Configure CDN to compress assets (if not already compressed):

- Enable Brotli compression
- Enable Gzip as fallback
- Assets are compressible (JS, CSS, JSON)

### Monitor CDN Usage

Track:

- Bandwidth usage (should move from origin to CDN)
- Cache hit rate (should be >95%)
- Origin requests (should drop significantly)

## Rollback Procedure

To disable CDN_HOST:

1. Build new image without `--build-arg CDN_HOST`
2. Deploy new image
3. Assets will revert to relative paths: `/packs/...`

No data loss or downtime required.

## Advanced: Multiple Environments

Different CDN for staging vs production:

```bash
# Staging
docker build --build-arg CDN_HOST=https://cdn-staging.example.com -t mastodon:staging .

# Production
docker build --build-arg CDN_HOST=https://cdn.example.com -t mastodon:production .
```

## FAQ

**Q: Do I need to rebuild for each CDN change?**
A: Yes, CDN_HOST is set at build time. However, you can change CDN configuration (caching rules, etc.) without rebuilding.

**Q: Can I use a relative path?**
A: No, CDN_HOST must be a full URL with protocol (https://...).

**Q: Does this affect user-uploaded media?**
A: No, user uploads use S3/object storage configured separately via `S3_*` environment variables.

**Q: What about emoji and custom emoji?**
A: Static emoji data is included in `/packs/emoji/` and served from CDN. Custom emoji (user-uploaded) uses S3.

**Q: Do I need CDN_HOST for development?**
A: No, CDN_HOST is only used for production builds. Development uses local Vite dev server.

**Q: Can I test CDN_HOST locally?**
A: Yes, set `CDN_HOST=https://cdn-test.example.com` and run `yarn build:production`, then serve `public/packs/` with a local server on that URL.

## Support

For issues or questions:

- Check CI test results: `.github/workflows/test-cdn-assets.yml`
- Review investigation notes: `CDN_HOST-INVESTIGATION.md`
- Search existing issues: GitHub issues with "CDN" or "asset_host" tags
