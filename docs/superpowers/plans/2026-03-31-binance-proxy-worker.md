# Binance Proxy Worker Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Route Binance API calls through a Cloudflare Worker to bypass Railway/AWS geo-restriction.

**Architecture:** A Cloudflare Worker receives already-signed requests from Rails, validates a shared secret (`X-Proxy-Token`), strips that header, and forwards the request to `fapi.binance.com`. Rails `HttpClient` is updated to use the proxy URL and token when env vars are present, falling back to direct Binance access when they're absent (local dev).

**Tech Stack:** Cloudflare Workers (JS), Ruby/Rails, Wrangler CLI (Cloudflare deploy tool).

---

## File Map

| Action | Path |
|--------|------|
| Create | `cloudflare/binance-proxy/worker.js` |
| Create | `cloudflare/binance-proxy/wrangler.toml` |
| Modify | `app/services/exchanges/binance/http_client.rb` |
| Create | `test/services/exchanges/binance/http_client_test.rb` |

---

## Task 1: Cloudflare Worker

**Files:**
- Create: `cloudflare/binance-proxy/worker.js`
- Create: `cloudflare/binance-proxy/wrangler.toml`

- [ ] **Step 1: Create the worker directory and files**

```bash
mkdir -p cloudflare/binance-proxy
```

Create `cloudflare/binance-proxy/worker.js`:

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

Create `cloudflare/binance-proxy/wrangler.toml`:

```toml
name = "binance-proxy"
main = "worker.js"
compatibility_date = "2024-01-01"
```

- [ ] **Step 2: Commit**

```bash
git add cloudflare/binance-proxy/worker.js cloudflare/binance-proxy/wrangler.toml
git commit -m "feat(cloudflare): Binance proxy worker"
```

- [ ] **Step 3: Deploy the Worker (manual — do this once)**

Prerequisites: Node.js installed.

```bash
npm install -g wrangler
cd cloudflare/binance-proxy
wrangler login        # opens browser → authenticate with your Cloudflare account
wrangler deploy       # deploys the worker; note the URL printed at the end
```

Expected output includes a line like:
```
Published binance-proxy (0.00 sec)
  https://binance-proxy.<your-subdomain>.workers.dev
```

- [ ] **Step 4: Set the Worker secret**

```bash
wrangler secret put PROXY_SECRET
```

When prompted, paste a strong random string. Generate one with:

```bash
openssl rand -hex 32
```

Keep this value — you'll need it as `BINANCE_PROXY_SECRET` on Railway.

- [ ] **Step 5: Smoke test the Worker**

```bash
curl -s -H "X-Proxy-Token: YOUR_SECRET" \
  "https://binance-proxy.<your-subdomain>.workers.dev/fapi/v1/premiumIndex?symbol=BTCUSDT"
```

Expected: JSON with `"markPrice"` field (Binance's response).

```bash
curl -s "https://binance-proxy.<your-subdomain>.workers.dev/fapi/v1/premiumIndex?symbol=BTCUSDT"
```

Expected: `Unauthorized` (401) — confirming the secret guard works.

---

## Task 2: Rails HttpClient — proxy support + tests

**Files:**
- Modify: `app/services/exchanges/binance/http_client.rb`
- Create: `test/services/exchanges/binance/http_client_test.rb`

- [ ] **Step 1: Write the failing tests**

Create `test/services/exchanges/binance/http_client_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

module Exchanges
  module Binance
    class HttpClientTest < ActiveSupport::TestCase
      setup do
        @api_key    = "test_key"
        @api_secret = "test_secret"
      end

      test "uses fapi.binance.com when BINANCE_PROXY_URL is not set" do
        with_env("BINANCE_PROXY_URL" => nil, "BINANCE_PROXY_SECRET" => nil) do
          client = HttpClient.new(api_key: @api_key, api_secret: @api_secret)
          assert_equal "https://fapi.binance.com", client.base_url
        end
      end

      test "uses BINANCE_PROXY_URL when set" do
        with_env("BINANCE_PROXY_URL" => "https://binance-proxy.example.workers.dev",
                 "BINANCE_PROXY_SECRET" => "secret123") do
          client = HttpClient.new(api_key: @api_key, api_secret: @api_secret)
          assert_equal "https://binance-proxy.example.workers.dev", client.base_url
        end
      end

      test "adds X-Proxy-Token header when BINANCE_PROXY_SECRET is set" do
        with_env("BINANCE_PROXY_URL" => "https://binance-proxy.example.workers.dev",
                 "BINANCE_PROXY_SECRET" => "secret123") do
          stub_http_response(body: '[{"symbol":"BTCUSDT"}]')
          client = HttpClient.new(api_key: @api_key, api_secret: @api_secret)

          captured_request = nil
          Net::HTTP.stub(:new, ->(_host, _port) {
            FakeHttp.new(captured_request_ref: ->(req) { captured_request = req },
                         body: '[{"symbol":"BTCUSDT"}]')
          }) do
            client.get("/fapi/v1/positionRisk") rescue nil
          end

          assert_not_nil captured_request
          assert_equal "secret123", captured_request["X-Proxy-Token"]
        end
      end

      test "does not add X-Proxy-Token header when BINANCE_PROXY_SECRET is not set" do
        with_env("BINANCE_PROXY_URL" => nil, "BINANCE_PROXY_SECRET" => nil) do
          client = HttpClient.new(api_key: @api_key, api_secret: @api_secret)

          captured_request = nil
          Net::HTTP.stub(:new, ->(_host, _port) {
            FakeHttp.new(captured_request_ref: ->(req) { captured_request = req },
                         body: '[{"symbol":"BTCUSDT"}]')
          }) do
            client.get("/fapi/v1/positionRisk") rescue nil
          end

          assert_not_nil captured_request
          assert_nil captured_request["X-Proxy-Token"]
        end
      end

      private

      # Temporarily override ENV keys for the duration of the block.
      def with_env(vars, &block)
        original = vars.keys.each_with_object({}) { |k, h| h[k] = ENV[k] }
        vars.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
        block.call
      ensure
        original.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
      end

      # Minimal Net::HTTP stand-in that captures the request and returns a stub response.
      class FakeHttp
        def initialize(captured_request_ref:, body:)
          @capture = captured_request_ref
          @body    = body
        end

        def use_ssl=(val); end
        def open_timeout=(val); end
        def read_timeout=(val); end

        def request(req)
          @capture.call(req)
          FakeResponse.new(@body)
        end
      end

      class FakeResponse
        attr_reader :body
        def initialize(body); @body = body; end
        def code; "200"; end
        def [](key); nil; end
        def blank?; false; end
      end
    end
  end
end
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
bin/rails test test/services/exchanges/binance/http_client_test.rb 2>&1 | tail -15
```

Expected: errors — `base_url` method does not exist on `HttpClient` yet.

- [ ] **Step 3: Implement the changes in HttpClient**

Current `app/services/exchanges/binance/http_client.rb` has these lines at the top of the class:

```ruby
DEFAULT_BASE_URL = "https://fapi.binance.com"

def initialize(api_key:, api_secret:, base_url: nil)
  @api_key = api_key
  @api_secret = api_secret
  @base_url = base_url.presence || DEFAULT_BASE_URL
end
```

And inside `get`:
```ruby
req = Net::HTTP::Get.new(uri)
req["X-MBX-APIKEY"] = @api_key
```

Replace the entire file with:

```ruby
# frozen_string_literal: true

require "net/http"
require "openssl"

module Exchanges
  module Binance
    # Signed GET for Binance USDⓈ-M Futures API. Builds URI, signs with HMAC-SHA256 on query string,
    # sends request, parses JSON. Raises Exchanges::ApiError for 429, 5xx, timeouts, empty body, parse errors.
    # When BINANCE_PROXY_URL is set, requests are routed through the Cloudflare Worker proxy to bypass
    # Railway/AWS geo-restriction. The proxy secret is sent via X-Proxy-Token and validated by the Worker.
    class HttpClient
      DEFAULT_BASE_URL = "https://fapi.binance.com"

      attr_reader :base_url

      def initialize(api_key:, api_secret:, base_url: nil)
        @api_key    = api_key
        @api_secret = api_secret
        @base_url   = base_url.presence || ENV["BINANCE_PROXY_URL"].presence || DEFAULT_BASE_URL
      end

      def get(path, params = {})
        if @api_secret.blank?
          raise ArgumentError, "Binance API secret is missing. Ensure the exchange account credentials are set and encryption is available in this process."
        end

        params = params.merge("timestamp" => (Time.now.to_f * 1000).to_i)
        query = params.sort.map { |k, v| "#{k}=#{v}" }.join("&")
        signature = OpenSSL::HMAC.hexdigest("SHA256", @api_secret, query)

        uri = URI("#{@base_url}#{path}")
        uri.query = "#{query}&signature=#{signature}"

        req = Net::HTTP::Get.new(uri)
        req["X-MBX-APIKEY"] = @api_key
        req["X-Proxy-Token"] = ENV["BINANCE_PROXY_SECRET"] if ENV["BINANCE_PROXY_SECRET"].present?

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.open_timeout = 10
        http.read_timeout = 15
        res = http.request(req)

        code = res.code.to_s
        if code != "200"
          parsed = (JSON.parse(res.body) if res.body.presence) rescue nil
          msg = parsed&.dig("msg") || parsed&.dig("message") || res.body.to_s[0..500]
          if msg.to_s.include?("restricted location") || msg.to_s.include?("Eligibility")
            raise ApiError, "Binance API is geo-restricted from this server's location. Binance blocks access from certain cloud providers (e.g. AWS/Railway). Trades cannot be synced from this host."
          end
          if code == "429" || code.start_with?("5")
            retry_after = res["Retry-After"]&.to_i
            raise ApiError.new("Binance API error #{code}: #{msg}", response_code: code, retry_after: retry_after)
          end
          raise "Binance API error #{code}: #{msg}"
        end

        if res.body.blank?
          raise ApiError, "Binance API returned empty body (status 200)"
        end

        begin
          JSON.parse(res.body)
        rescue JSON::ParserError => e
          snippet = res.body.to_s[0..200].gsub(/\s+/, " ")
          raise ApiError, "Binance API non-JSON response: #{snippet}. #{e.message}"
        end
      rescue Net::OpenTimeout, Net::ReadTimeout, Timeout::Error => e
        raise ApiError, "Binance API timeout: #{e.message}"
      end
    end
  end
end
```

- [ ] **Step 4: Run tests to confirm they pass**

```bash
bin/rails test test/services/exchanges/binance/http_client_test.rb 2>&1 | tail -10
```

Expected: 4 runs, 0 failures, 0 errors.

- [ ] **Step 5: Run the full test suite**

```bash
bin/rails test 2>&1 | tail -10
```

Expected: 0 failures, 0 errors.

- [ ] **Step 6: Commit**

```bash
git add app/services/exchanges/binance/http_client.rb \
        test/services/exchanges/binance/http_client_test.rb
git commit -m "feat(binance): route requests through Cloudflare Worker proxy when BINANCE_PROXY_URL is set"
```

---

## Task 3: Set env vars on Railway and verify

This task is manual (no code changes).

- [ ] **Step 1: Set env vars on Railway**

In the Railway dashboard for your app:

| Variable | Value |
|---|---|
| `BINANCE_PROXY_URL` | `https://binance-proxy.<your-subdomain>.workers.dev` |
| `BINANCE_PROXY_SECRET` | The same secret you set with `wrangler secret put PROXY_SECRET` |

Railway will redeploy automatically.

- [ ] **Step 2: Trigger a sync and verify**

After deploy, go to `/exchange_accounts`, trigger a Binance sync ("Sync now" or "Historic sync"), and confirm:
- No "geo-restricted" error in the sync failed badge
- Trades appear in the account

- [ ] **Step 3: Push**

```bash
git push origin master
```
