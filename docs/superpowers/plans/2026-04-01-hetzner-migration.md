# Hetzner Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the Rails app from Railway to an existing Hetzner instance so Binance API calls work without a proxy.

**Architecture:** Docker containers managed by Kamal 2 on the existing Hetzner instance — `kamal-proxy` for SSL, `web` for Rails/Puma, `job` for Solid Queue, and a `postgres` accessory for PostgreSQL 16. Images pushed to GitHub Container Registry (ghcr.io).

**Tech Stack:** Kamal 2, Docker, PostgreSQL 16, GitHub Container Registry, Let's Encrypt (via kamal-proxy).

---

## File Map

| Action | Path |
|--------|------|
| Delete | `cloudflare/binance-proxy/worker.js` |
| Delete | `cloudflare/binance-proxy/wrangler.toml` |
| Delete | `test/services/exchanges/binance/http_client_test.rb` |
| Modify | `app/services/exchanges/binance/http_client.rb` |
| Modify | `app/services/exchanges/binance_client.rb` |
| Modify | `config/deploy.yml` |
| Modify | `config/database.yml` |
| Modify | `.kamal/secrets` (gitignored — never committed) |

---

## Task 1: Remove Cloudflare proxy code

Removes all proxy-specific files and reverts the two Rails files that were changed to support the Cloudflare Worker proxy. The proxy approach was abandoned because Binance blocks Cloudflare IPs too.

**Files:**
- Delete: `cloudflare/binance-proxy/worker.js`
- Delete: `cloudflare/binance-proxy/wrangler.toml`
- Delete: `test/services/exchanges/binance/http_client_test.rb`
- Modify: `app/services/exchanges/binance/http_client.rb`
- Modify: `app/services/exchanges/binance_client.rb`

- [ ] **Step 1: Delete the Cloudflare directory and test file**

```bash
rm -rf cloudflare/
rm test/services/exchanges/binance/http_client_test.rb
```

- [ ] **Step 2: Revert app/services/exchanges/binance/http_client.rb**

Replace the entire file with this content:

```ruby
# frozen_string_literal: true

require "net/http"
require "openssl"

module Exchanges
  module Binance
    # Signed GET for Binance USDⓈ-M Futures API. Builds URI, signs with HMAC-SHA256 on query string,
    # sends request, parses JSON. Raises Exchanges::ApiError for 429, 5xx, timeouts, empty body, parse errors.
    # Optional base_url argument for testnet (https://testnet.binancefuture.com).
    class HttpClient
      DEFAULT_BASE_URL = "https://fapi.binance.com"

      def initialize(api_key:, api_secret:, base_url: nil)
        @api_key    = api_key
        @api_secret = api_secret
        @base_url   = base_url.presence || DEFAULT_BASE_URL
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

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.open_timeout = 10
        http.read_timeout = 15
        res = http.request(req)

        code = res.code.to_s
        if code != "200"
          parsed = (JSON.parse(res.body) if res.body.presence) rescue nil
          msg = parsed&.dig("msg") || parsed&.dig("message") || res.body.to_s[0..500]
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

- [ ] **Step 3: Revert app/services/exchanges/binance_client.rb**

In `app/services/exchanges/binance_client.rb`, line 33 currently reads:
```ruby
        base_url: base_url.presence
```

Change it back to:
```ruby
        base_url: base_url.presence || BASE_URL
```

- [ ] **Step 4: Run tests**

```bash
bin/rails test 2>&1 | tail -10
```

Expected: 0 failures, 0 errors.

- [ ] **Step 5: Commit**

```bash
git add app/services/exchanges/binance/http_client.rb \
        app/services/exchanges/binance_client.rb
git rm -r cloudflare/
git rm test/services/exchanges/binance/http_client_test.rb
git commit -m "chore: remove Cloudflare proxy — migrating to Hetzner eliminates geo-restriction"
```

---

## Task 2: Fix database.yml for separate queue database

The production `queue` database needs to use `QUEUE_DATABASE_URL` so Solid Queue jobs land in `soldier_trades_tracker_queue` while app data stays in `soldier_trades_tracker_production`. Falls back to `DATABASE_URL` if `QUEUE_DATABASE_URL` is not set (keeps Railway working during the transition).

**Files:**
- Modify: `config/database.yml`

- [ ] **Step 1: Update config/database.yml**

Change the production section from:
```yaml
production:
  primary:
    <<: *default
    url: <%= ENV["DATABASE_URL"] %>
  queue:
    <<: *default
    url: <%= ENV["DATABASE_URL"] %>
```

To:
```yaml
production:
  primary:
    <<: *default
    url: <%= ENV["DATABASE_URL"] %>
  queue:
    <<: *default
    url: <%= ENV["QUEUE_DATABASE_URL"] || ENV["DATABASE_URL"] %>
```

- [ ] **Step 2: Run tests**

```bash
bin/rails test 2>&1 | tail -5
```

Expected: 0 failures, 0 errors.

- [ ] **Step 3: Commit**

```bash
git add config/database.yml
git commit -m "chore: use QUEUE_DATABASE_URL for production queue database"
```

---

## Task 3: Configure config/deploy.yml

Replaces the placeholder template with the real deployment configuration for Hetzner.

**Files:**
- Modify: `config/deploy.yml`

**Before starting this task, collect these three values:**
- `HETZNER_IP` — the public IP of your Hetzner instance (e.g. `65.21.100.200`)
- `DOMAIN` — the domain you registered and pointed at Hetzner (e.g. `trades.yourdomain.com`)
- `GITHUB_USERNAME` — your GitHub username (e.g. `sgcastillo`)

- [ ] **Step 1: Replace config/deploy.yml with the final content**

Replace the entire file, substituting your actual values for `HETZNER_IP`, `DOMAIN`, and `GITHUB_USERNAME`:

```yaml
service: soldier-trades-tracker
image: ghcr.io/GITHUB_USERNAME/soldier-trades-tracker

servers:
  web:
    - HETZNER_IP
  job:
    hosts:
      - HETZNER_IP
    cmd: bin/jobs

proxy:
  ssl: true
  host: DOMAIN

registry:
  server: ghcr.io
  username: GITHUB_USERNAME
  password:
    - KAMAL_REGISTRY_PASSWORD

builder:
  arch: amd64

env:
  secret:
    - RAILS_MASTER_KEY
    - DATABASE_URL
    - QUEUE_DATABASE_URL
    - ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY
    - ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY
    - ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT
    - COINGECKO_API_KEY
    - IOL_USERNAME
    - IOL_PASSWORD

accessories:
  postgres:
    image: postgres:16
    host: HETZNER_IP
    port: "127.0.0.1:5432:5432"
    env:
      secret:
        - POSTGRES_PASSWORD
    directories:
      - data:/var/lib/postgresql/data
```

- [ ] **Step 2: Commit**

```bash
git add config/deploy.yml
git commit -m "chore(deploy): configure Kamal deployment for Hetzner"
```

---

## Task 4: Push branch to master

Merge all code changes to master so Kamal builds from the correct branch.

- [ ] **Step 1: Switch to master and merge**

```bash
git checkout master
git merge feat/app-hardening-and-performance
```

- [ ] **Step 2: Push**

```bash
git push origin master
```

---

## Task 5: Register domain and point DNS (manual)

Let's Encrypt (used by kamal-proxy for SSL) requires a valid DNS A record pointing at the server before `kamal deploy` can provision a certificate. Do this now so DNS has time to propagate before the deploy step.

- [ ] **Step 1: Register a domain**

Purchase a domain from any registrar (Namecheap, Cloudflare Registrar, Porkbun, etc.). A subdomain of an existing domain works too (e.g. `trades.yourdomain.com`).

- [ ] **Step 2: Create an A record pointing to your Hetzner IP**

In your registrar's DNS panel, create:
```
Type: A
Name: @ (or trades, or whatever subdomain)
Value: HETZNER_IP
TTL: 300 (or lowest available)
```

- [ ] **Step 3: Verify DNS propagation**

```bash
dig +short YOUR_DOMAIN
```

Expected: returns your Hetzner IP. May take a few minutes. Continue to the next task once it resolves.

---

## Task 6: Prepare Hetzner server (manual)

This task runs on your Hetzner server via SSH. No code changes.

- [ ] **Step 1: SSH into Hetzner**

```bash
ssh root@HETZNER_IP
```

- [ ] **Step 2: Install Docker**

```bash
curl -fsSL https://get.docker.com | sh
```

Verify Docker is running:
```bash
docker --version
docker ps
```

Expected: Docker version output and empty container list.

- [ ] **Step 3: Exit back to your local machine**

```bash
exit
```

---

## Task 7: Create .kamal/secrets (manual — never commit this file)

`.kamal/secrets` is already in `.gitignore`. This file is read by Kamal to inject environment variables into containers. You need values from Railway (Dashboard → your app → Variables).

- [ ] **Step 1: Create GitHub PAT for ghcr.io**

Go to https://github.com/settings/tokens → Generate new token (classic) → check `write:packages` scope → copy the token (starts with `ghp_`).

- [ ] **Step 2: Generate a strong Postgres password**

Run locally:
```bash
openssl rand -hex 32
```

Save this value — you'll use it as `POSTGRES_PASSWORD` and embed it in both database URLs.

- [ ] **Step 3: Write .kamal/secrets**

Replace the entire `.kamal/secrets` file with the following, filling in each value:

```bash
KAMAL_REGISTRY_PASSWORD=ghp_YOUR_GITHUB_PAT

RAILS_MASTER_KEY=                          # copy from Railway vars or config/master.key

POSTGRES_PASSWORD=YOUR_STRONG_RANDOM_PASSWORD

DATABASE_URL=postgresql://postgres:YOUR_STRONG_RANDOM_PASSWORD@soldier-trades-tracker-postgres:5432/soldier_trades_tracker_production

QUEUE_DATABASE_URL=postgresql://postgres:YOUR_STRONG_RANDOM_PASSWORD@soldier-trades-tracker-postgres:5432/soldier_trades_tracker_queue

ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=      # copy from Railway vars
ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY= # copy from Railway vars
ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT= # copy from Railway vars

COINGECKO_API_KEY=                         # copy from Railway vars
IOL_USERNAME=                              # copy from Railway vars
IOL_PASSWORD=                              # copy from Railway vars
```

Note: The `DATABASE_URL` and `QUEUE_DATABASE_URL` use `soldier-trades-tracker-postgres` as the hostname — this is the Docker network name Kamal assigns to the postgres accessory container. Do not use `localhost` or the Hetzner IP here.

---

## Task 8: kamal setup (manual)

Installs `kamal-proxy` on the Hetzner server. Run from your local machine in the repo root.

- [ ] **Step 1: Install kamal gem if not already installed**

```bash
gem install kamal
```

- [ ] **Step 2: Run kamal setup**

```bash
kamal setup
```

This will:
- SSH into Hetzner
- Install `kamal-proxy` as a Docker container
- Configure it to handle ports 80 and 443 with Let's Encrypt

Expected output ends with: `Finished all in X seconds`

If it asks about Docker already being installed, that's fine — kamal-proxy installs alongside it.

---

## Task 9: Boot PostgreSQL and create databases (manual)

- [ ] **Step 1: Boot the postgres accessory**

```bash
kamal accessory boot postgres
```

Expected: Docker pulls `postgres:16`, creates the container, starts it.

- [ ] **Step 2: Create both databases**

```bash
kamal accessory exec postgres "createdb -U postgres soldier_trades_tracker_production"
kamal accessory exec postgres "createdb -U postgres soldier_trades_tracker_queue"
```

Expected: No output (success is silent for createdb).

- [ ] **Step 3: Verify both databases exist**

```bash
kamal accessory exec postgres "psql -U postgres -c '\l' | grep soldier"
```

Expected: Two rows — `soldier_trades_tracker_production` and `soldier_trades_tracker_queue`.

---

## Task 10: Migrate primary database from Railway (manual)

The queue database is left empty — Kamal will run `db:migrate` on first deploy which creates Solid Queue tables fresh. Only the primary database (app data) needs migrating.

- [ ] **Step 1: Get Railway's public database URL**

In Railway Dashboard → select your PostgreSQL service → Connect tab → copy the **Public URL**. It looks like:
```
postgresql://postgres:PASSWORD@roundhouse.proxy.rlwy.net:PORT/railway
```

Store it in your shell:
```bash
export RAILWAY_DB_URL="postgresql://postgres:PASSWORD@roundhouse.proxy.rlwy.net:PORT/railway"
```

- [ ] **Step 2: Export the database from Railway**

Run locally:
```bash
pg_dump $RAILWAY_DB_URL \
  --no-acl --no-owner -Fc \
  -f soldier_trades_tracker.dump
```

Expected: Creates `soldier_trades_tracker.dump` in the current directory (may take 10–60 seconds depending on data size).

- [ ] **Step 3: Copy dump to Hetzner**

```bash
scp soldier_trades_tracker.dump root@HETZNER_IP:/tmp/
```

- [ ] **Step 4: Restore on Hetzner**

```bash
ssh root@HETZNER_IP \
  "docker exec -i soldier-trades-tracker-postgres \
   pg_restore -U postgres -d soldier_trades_tracker_production \
   /tmp/soldier_trades_tracker.dump"
```

Expected: No errors. Some "already exists" warnings are normal if schemas/types overlap.

- [ ] **Step 5: Clean up the dump file**

```bash
ssh root@HETZNER_IP "rm /tmp/soldier_trades_tracker.dump"
rm soldier_trades_tracker.dump
```

---

## Task 11: Deploy app (manual)

- [ ] **Step 1: Deploy**

```bash
kamal deploy
```

This will:
1. Build the Docker image locally (may take 3–5 minutes on first build)
2. Push it to ghcr.io
3. SSH into Hetzner and pull the image
4. Start `web` container (Rails/Puma)
5. Start `job` container (Solid Queue `bin/jobs`)
6. Run `db:migrate` on the primary database
7. Register both containers with kamal-proxy

Expected output ends with: `Finished all in X seconds`

- [ ] **Step 2: Verify the web container is running**

```bash
kamal app logs
```

Expected: Puma boot messages, no crash logs.

```bash
kamal app logs -r job
```

Expected: Solid Queue worker boot messages.

- [ ] **Step 3: Open the app in a browser**

Navigate to `https://DOMAIN`. You should see the login page with a valid SSL certificate.

- [ ] **Step 4: Trigger a Binance sync**

Log in → go to Exchange Accounts → click "Sync now" on your Binance account. Confirm trades load without a geo-restriction error.

---

## Task 12: Railway shutdown (manual)

Only do this after verifying everything works on Hetzner.

- [ ] **Step 1: Confirm Hetzner is healthy**

All of the following must be true before cutting over:
- App loads at `https://DOMAIN`
- Binance sync returns trades
- No error logs in `kamal app logs`

- [ ] **Step 2: Shut down Railway**

In Railway Dashboard → your project → Settings → Danger Zone → Delete project (or just pause the service if you want a safety net for a few days).

Railway stays live until you delete it — there is no data loss risk since your Hetzner database already has the restored data and any new trades will sync from the exchanges.
