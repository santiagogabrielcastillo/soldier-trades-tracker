# Binance Proxy Worker Design

**Date:** 2026-03-31
**Status:** Approved

## Context

Binance's authenticated API (`fapi.binance.com`) is geo-restricted from Railway's AWS-based servers. The app cannot sync Binance trades automatically. The solution is a Cloudflare Worker that acts as a transparent HTTP proxy: Rails sends already-signed requests to the Worker, which validates a shared secret and forwards them to Binance. Cloudflare IPs are not geo-blocked by Binance.

## Architecture and Data Flow

```
Rails (Railway/AWS)
  → GET https://binance-proxy.<subdomain>.workers.dev/fapi/v1/userTrades?...&signature=...
    Headers: X-MBX-APIKEY: {user api key}
             X-Proxy-Token: {shared secret}

Cloudflare Worker
  1. Validate X-Proxy-Token == PROXY_SECRET env var → 401 if mismatch
  2. Strip X-Proxy-Token header
  3. Forward to https://fapi.binance.com{same path + query string}
     with remaining headers intact (X-MBX-APIKEY preserved)
  4. Return Binance's response unchanged (status code, body, headers)

Binance API (fapi.binance.com)
  → Responds normally (Cloudflare IPs are not geo-blocked)
```

No re-signing in the Worker. Rails already produces a valid HMAC-SHA256 signed query string before the request leaves; the Worker is a geographic relay only.

## Cloudflare Worker

**Location in repo:** `cloudflare/binance-proxy/` (tracked in git; secret never committed)

**Files:**
- `cloudflare/binance-proxy/worker.js` — the Worker handler
- `cloudflare/binance-proxy/wrangler.toml` — Wrangler config (worker name, compatibility date)

**`worker.js`:**
```js
export default {
  async fetch(request, env) {
    const token = request.headers.get("X-Proxy-Token");
    if (token !== env.PROXY_SECRET) {
      return new Response("Unauthorized", { status: 401 });
    }

    const url = new URL(request.url);
    const target = new URL("https://fapi.binance.com");
    target.pathname = url.pathname;
    target.search = url.search;

    const headers = new Headers(request.headers);
    headers.delete("X-Proxy-Token");

    return fetch(target.toString(), { method: "GET", headers });
  }
};
```

**`wrangler.toml`:**
```toml
name = "binance-proxy"
main = "worker.js"
compatibility_date = "2024-01-01"
```

**Worker secret:** `PROXY_SECRET` — set via `wrangler secret put PROXY_SECRET` (never in git or wrangler.toml).

**One-time deployment steps:**
1. Create Cloudflare account (free tier)
2. `npm install -g wrangler`
3. `wrangler login`
4. From `cloudflare/binance-proxy/`: `wrangler deploy`
5. `wrangler secret put PROXY_SECRET` → paste the shared secret
6. Note the Worker URL: `https://binance-proxy.<subdomain>.workers.dev`

## Rails Changes

**`app/services/exchanges/binance/http_client.rb`:**

Two changes:
1. Replace hardcoded `DEFAULT_BASE_URL = "https://fapi.binance.com"` with env-aware default:
   ```ruby
   DEFAULT_BASE_URL = ENV["BINANCE_PROXY_URL"].presence || "https://fapi.binance.com"
   ```
2. Add `X-Proxy-Token` header when `BINANCE_PROXY_SECRET` is set:
   ```ruby
   req["X-Proxy-Token"] = ENV["BINANCE_PROXY_SECRET"] if ENV["BINANCE_PROXY_SECRET"].present?
   ```

No other files change. `BinanceClient`, `SyncService`, and all callers are unaffected.

**New Railway env vars:**
| Variable | Value |
|---|---|
| `BINANCE_PROXY_URL` | `https://binance-proxy.<subdomain>.workers.dev` |
| `BINANCE_PROXY_SECRET` | A strong random string (e.g. `openssl rand -hex 32`) |

**Local development:** Neither variable is set → Rails calls `fapi.binance.com` directly (works fine locally).

## Testing

**`test/services/exchanges/binance/http_client_test.rb`** (new file):

- With `BINANCE_PROXY_URL` set: assert request goes to the proxy URL, assert `X-Proxy-Token` header is present
- Without `BINANCE_PROXY_URL`: assert request goes to `fapi.binance.com`, assert no `X-Proxy-Token` header

Both tests stub `Net::HTTP` to avoid real network calls.

**Manual smoke test after deploy:**
```bash
curl -H "X-Proxy-Token: your_secret" \
  "https://binance-proxy.<subdomain>.workers.dev/fapi/v1/premiumIndex?symbol=BTCUSDT"
# Expected: Binance mark price JSON
```

Then trigger a sync from the app UI and confirm trades are fetched.
