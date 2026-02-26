# Deployment (Kamal)

This app is set up for [Kamal](https://kamal-deploy.org/) with two roles: **web** (Rails server) and **job** (Solid Queue worker via `bin/jobs`).

## Prerequisites

- Kamal installed (`gem install kamal` or via Gemfile)
- SSH access to your servers
- Docker on servers (Kamal installs it via `kamal setup` if needed)
- Production database (PostgreSQL) reachable from the app servers

## Configure servers and env

1. **Edit `config/deploy.yml`**
   - Set `servers.web` and `servers.job` to your host(s) (replace `192.168.0.1`).
   - Set `proxy.host` to your public hostname (e.g. `app.example.com`).

2. **Secrets (env in containers)**  
   Create `.kamal/secrets` (gitignored) with one `KEY=value` per line. Required and optional vars:

   | Variable | Required | Notes |
   |----------|----------|--------|
   | `RAILS_MASTER_KEY` | Yes | Decrypts `config/credentials/production.key` / credentials. Needed for credentials-based DB and encryption. |
   | `SOLDIER_TRADES_TRACKER_DATABASE_PASSWORD` | Yes | Production DB password (see `config/database.yml`). |

   Optional (only if you don’t store them in credentials):

   - `ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY`
   - `ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY`
   - `ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT`

   Example `.kamal/secrets`:

   ```
   RAILS_MASTER_KEY=your-master-key
   SOLDIER_TRADES_TRACKER_DATABASE_PASSWORD=your-db-password
   ```

3. **Expose secrets to Kamal**  
   In `config/deploy.yml`, under `env.secret`, list the same names (e.g. `RAILS_MASTER_KEY`, `SOLDIER_TRADES_TRACKER_DATABASE_PASSWORD`), then uncomment the `env:` block. Kamal will inject these into the containers from `.kamal/secrets`.

4. **Database host**  
   Production `config/database.yml` does not set a DB host; it uses default localhost. If the DB is on another host, set the host (or full URL) via env and adjust `database.yml` to use `ENV["DB_HOST"]` or `ENV["DATABASE_URL"]` for production.

## Deploy

```bash
# One-time: install Docker and prepare servers
kamal setup

# Deploy app (builds images, runs migrations, starts web + job)
kamal deploy
```

Migrations run automatically on deploy (Kamal runs the app’s migration command).

## Verify

- **Web:** Open `https://<proxy.host>` and confirm the app loads; log in or add an exchange account if applicable.
- **Job (Solid Queue):** After adding an exchange account, trigger a sync (e.g. from the UI or by enqueueing `SyncExchangeAccountJob`). Check logs for the job role to confirm workers run and no errors.
- **Encryption:** If you use encrypted attributes (e.g. API keys), confirm `RAILS_MASTER_KEY` (and any encryption keys in credentials or ENV) are set so decryption works in production.

## Rollback

```bash
kamal rollback
```

## Notes

- Keep `.kamal/secrets` out of version control (it should be in `.gitignore`).
- Use a strong `RAILS_MASTER_KEY` and DB password in production; rotate them via your credentials/secrets process and redeploy.
