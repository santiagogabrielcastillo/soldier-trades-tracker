# Hetzner Migration Design

**Date:** 2026-04-01
**Status:** Approved

## Context

The app runs on Railway (AWS-based). Binance's API (`fapi.binance.com`) geo-blocks all AWS/datacenter IPs including Railway and Cloudflare Workers. Moving the entire app to Hetzner eliminates the geo-restriction entirely — no proxy needed. The existing Hetzner instance (4GB RAM, 2 CPUs, ~763MB currently used) has sufficient headroom for Rails + PostgreSQL + Solid Queue alongside the existing trading bot.

## Architecture

```
Hetzner instance
  ├── kamal-proxy         (SSL termination, Let's Encrypt, port 80/443)
  ├── soldier-trades-tracker-web    (Rails / Puma)
  ├── soldier-trades-tracker-job    (Solid Queue worker, bin/jobs)
  └── soldier-trades-tracker-postgres  (PostgreSQL 16 accessory, persistent volume)
```

Docker manages all containers. Kamal 2 handles builds, deploys, and process management. Images are pushed to GitHub Container Registry (ghcr.io — free). A registered domain is required for Let's Encrypt SSL.

Two databases inside the same PostgreSQL container:
- `soldier_trades_tracker_production` — primary app data
- `soldier_trades_tracker_queue` — Solid Queue jobs (recreated fresh, no migration needed)

## `config/deploy.yml`

```yaml
service: soldier-trades-tracker
image: ghcr.io/YOUR_GITHUB_USERNAME/soldier-trades-tracker

servers:
  web:
    - YOUR_HETZNER_IP
  job:
    hosts:
      - YOUR_HETZNER_IP
    cmd: bin/jobs

proxy:
  ssl: true
  host: YOUR_DOMAIN

registry:
  server: ghcr.io
  username: YOUR_GITHUB_USERNAME
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
    host: YOUR_HETZNER_IP
    port: "127.0.0.1:5432:5432"
    env:
      secret:
        - POSTGRES_PASSWORD
    directories:
      - data:/var/lib/postgresql/data
```

## `.kamal/secrets` (gitignored — never committed)

```bash
KAMAL_REGISTRY_PASSWORD=ghp_...        # GitHub PAT with packages:write scope
RAILS_MASTER_KEY=...                   # copy from Railway
POSTGRES_PASSWORD=<strong random password>
DATABASE_URL=postgresql://postgres:<POSTGRES_PASSWORD>@soldier-trades-tracker-postgres:5432/soldier_trades_tracker_production
QUEUE_DATABASE_URL=postgresql://postgres:<POSTGRES_PASSWORD>@soldier-trades-tracker-postgres:5432/soldier_trades_tracker_queue
ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=...
ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY=...
ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT=...
COINGECKO_API_KEY=...
IOL_USERNAME=...
IOL_PASSWORD=...
```

`BINANCE_PROXY_URL` and `BINANCE_PROXY_SECRET` are not included — no proxy needed on Hetzner.

## Database Migration

Only the primary database needs migrating. The queue database is recreated fresh.

```bash
# 1. Get Railway's PUBLIC database URL
#    Railway Dashboard → postgres service → Connect → Public URL

# 2. Export from Railway (run locally)
pg_dump $RAILWAY_PUBLIC_DB_URL \
  --no-acl --no-owner -Fc \
  -f soldier_trades_tracker.dump

# 3. Boot PostgreSQL accessory on Hetzner
kamal accessory boot postgres

# 4. Create databases
kamal accessory exec postgres "createdb -U postgres soldier_trades_tracker_production"
kamal accessory exec postgres "createdb -U postgres soldier_trades_tracker_queue"

# 5. Copy dump to Hetzner and restore
scp soldier_trades_tracker.dump root@YOUR_HETZNER_IP:/tmp/
ssh root@YOUR_HETZNER_IP \
  "docker exec -i soldier-trades-tracker-postgres \
   pg_restore -U postgres -d soldier_trades_tracker_production \
   /tmp/soldier_trades_tracker.dump"

# 6. Deploy (runs migrations on top of restored data)
kamal deploy
```

Railway stays live until DNS is cut over — zero data loss risk.

## Deployment Steps (ordered)

1. Register a domain, point A record to Hetzner IP
2. Install Docker on Hetzner: `curl -fsSL https://get.docker.com | sh`
3. Create GitHub PAT (`packages:write` scope) at github.com/settings/tokens
4. Fill in `config/deploy.yml` (IP, domain, GitHub username)
5. Create `.kamal/secrets` with all values from Railway
6. `kamal setup` — installs kamal-proxy on server
7. `kamal accessory boot postgres` — starts PostgreSQL container
8. Migrate database (steps above)
9. `kamal deploy` — builds image, pushes to ghcr.io, starts web + job containers
10. Verify: open the domain, trigger a Binance sync, confirm trades load
11. Shut down Railway

## Cleanup (code changes)

Remove the Cloudflare Worker proxy — no longer needed:

1. Delete `cloudflare/` directory
2. Revert `app/services/exchanges/binance/http_client.rb` proxy changes:
   - Remove `attr_reader :base_url`
   - Change `@base_url` back to `base_url.presence || DEFAULT_BASE_URL`
   - Remove `X-Proxy-Token` header line
3. Revert `app/services/exchanges/binance_client.rb`:
   - Change `base_url: base_url.presence` back to `base_url: base_url.presence || BASE_URL`
4. Delete `test/services/exchanges/binance/http_client_test.rb`

## What Does Not Change

- All application code, models, jobs, sync logic — untouched
- `config/database.yml` — already configured for two databases with `DATABASE_URL` / `QUEUE_DATABASE_URL` env vars
- Existing `Dockerfile` — used as-is by Kamal
