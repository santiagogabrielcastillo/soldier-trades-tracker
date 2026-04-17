# BYOK API Keys Design

**Date:** 2026-04-17
**Topic:** byok-api-keys

## What We're Building

Move all platform-owned external API keys (Finnhub, IOL, CoinGecko, Anthropic/Claude) to a Bring Your Own Key (BYOK) model. Users store their own keys in the app; the app no longer relies on env vars or Rails credentials for these services. When a key is missing, the UI prompts the user to configure it. Gemini is already partially BYOK — its key moves into the new unified storage model.

## Why This Approach

We considered adding columns directly to the `User` model (like the existing `gemini_api_key`), but IOL requires two fields (username + password) and the number of providers makes a column-per-key approach unwieldy. A generic `user_api_keys` join table handles all providers uniformly and is easy to extend.

## Data Model

New table `user_api_keys`:

| column | type | notes |
|---|---|---|
| `id` | bigint PK | |
| `user_id` | bigint FK | |
| `provider` | string | enum: `finnhub`, `coingecko`, `iol`, `anthropic`, `gemini` |
| `key` | text | encrypted via Active Record Encryption |
| `secret` | text | encrypted — IOL password; nil for all other providers |
| `created_at` | datetime | |
| `updated_at` | datetime | |

- Unique index on `[user_id, provider]`
- Model: `UserApiKey`, `belongs_to :user`
- `encrypts :key, :secret` via Active Record Encryption

Helper on `User`:
```ruby
def api_key_for(provider)
  user_api_keys.find_by(provider: provider)
end
```

Class-level helpers on `UserApiKey`:
```ruby
def self.key_for(user, provider)
  user.user_api_keys.find_by(provider: provider)&.key
end

def self.credentials_for(user, provider)
  row = user.user_api_keys.find_by(provider: provider)
  row ? { key: row.key, secret: row.secret } : nil
end
```

**Gemini migration:** Backfill `users.gemini_api_key` → `user_api_keys` rows (`provider: :gemini`, `key: gemini_api_key`), then drop the `gemini_api_key` column from users.

## Service Layer

Each service receives the resolved key rather than reading from env/credentials. All callers already receive `current_user` or pass a user object, so threading the user through is straightforward.

| Service | Key source change |
|---|---|
| `Stocks::FinnhubClient` | Accepts `api_key:` param; callers pass `UserApiKey.key_for(user, :finnhub)` |
| `Stocks::IolClient` | Accepts `username:, password:` params; callers pass from `UserApiKey.credentials_for(user, :iol)` |
| `Spot::CurrentPriceFetcher` (CoinGecko) | Receives `api_key:` from `UserApiKey.key_for(user, :coingecko)` |
| `Ai::ProviderForUser` | Checks `user_api_keys` for `:anthropic` first, then `:gemini`; both coexist |

Platform env vars (`FINNHUB_API_KEY`, `IOL_USERNAME`, `IOL_PASSWORD`, `COINGECKO_API_KEY`) and Rails credentials entries (`finnhub`, `iol`, `anthropic`) are removed after migration.

## Missing Key Prompt

When a key is not configured, the service call is skipped (returns empty result) and the controller sets a flash alert linking to the settings page:

```ruby
unless current_user.api_key_for(:finnhub)
  flash.now[:alert] = "Stock prices require a Finnhub API key. #{view_context.link_to('Configure it here', settings_api_keys_path)}"
end
```

Controllers affected: `StocksController`, `Stocks::ValuationCheckController`, `Stocks::PortfolioSnapshotController` (Finnhub), `StocksController` (IOL via `ArgentineCurrentPriceFetcher`), `SpotController` and `DashboardsController` (CoinGecko). The AI feature already handles the no-provider case gracefully.

## Settings UI

New unified "API Keys" settings section replacing the existing Gemini key UI.

**Routes:**
```ruby
namespace :settings do
  resources :api_keys, only: [:index, :destroy], param: :provider do
    collection { post :upsert }
  end
end
```

**Controller:** `Settings::ApiKeysController`
- `index` — lists all providers with configured/not-configured status
- `upsert` — create or update key for a provider (handles both new and existing rows)
- `destroy` — removes the key row for a provider

**UI:** A list of all providers, each showing:
- Provider name + description of what it's used for
- Status badge (configured / not configured)
- Configure / Remove button
- IOL shows two fields (username + password); all others show one field (key), masked on display

The existing Gemini key form in settings is removed; Gemini appears as one row in the unified list.

## Error Handling

- Services return empty/nil when called without a key — no exceptions
- Flash alerts in controllers guide users to configure missing keys
- `upsert` validates presence of `key` (and `secret` for IOL) before saving

## Testing

- Unit tests for `UserApiKey` model (scopes, helpers, encryption)
- Unit tests for each updated service client (key passed in, nil key → nil result)
- Controller tests verifying flash alert appears when key is missing
- Controller tests for `Settings::ApiKeysController` (index, upsert, destroy)
- Migration test: verify Gemini backfill moves keys correctly

## Open Questions

None — all design decisions resolved.
