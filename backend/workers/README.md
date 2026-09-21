# Personal Stylist Workers Backend

Cloudflare Workers backend for the Personal Stylist iOS app. It authenticates devices, keeps a
usage ledger, and serves the deterministic outfit engine (`file:../outfit-engine`).

Everything identifying in this directory is a **placeholder**: the Worker `name`s, the KV and
rate-limit namespace ids in `wrangler.toml`, and the spend-cap sample values.

## Configure and run wrangler

This repository ships **no deployment automation**, and the committed `wrangler.toml` is a sample
that must never be used against a real account. The one recipe:

1. `cp wrangler.toml wrangler.local.toml` (gitignored).
2. In `wrangler.local.toml`, set your own Worker `name`, KV id and rate-limit `namespace_id`.
   Named environments inherit nothing: each `[env.<name>]` you keep needs its own `name`, bindings
   and secrets — delete the ones you don't use.
3. Pass `--config wrangler.local.toml` — plus `--env <name>` for a named environment — to **every**
   wrangler command, so KV ids, secrets and deploys always belong to the same Worker and environment:

```bash
npx wrangler kv namespace create USAGE_LEDGER    --config wrangler.local.toml   # [--env <name>]; paste the id into that block
npx wrangler secret put OPENROUTER_API_KEY       --config wrangler.local.toml   # [--env <name>]
npx wrangler secret put ENROLLMENT_SECRET        --config wrangler.local.toml   # [--env <name>]
npx wrangler deploy                              --config wrangler.local.toml   # [--env <name>]
npx wrangler types --include-runtime=false       --config wrangler.local.toml   # only if you change the binding set
npm run dev                                      # = wrangler dev --config wrangler.local.toml
```

The committed `worker-configuration.d.ts` matches the binding set of the committed sample. The iOS
Simulator demo does **not** need any of this: it talks to the engine's local bridge
(`backend/outfit-engine`, `npm run serve:local`), not to a Worker.

### Issue a device token

Store it in the iOS Keychain only — never in Info.plist:

```bash
curl -sS -X POST https://<your-worker-host>/v1/auth/device \
  -H "Authorization: Bearer $ENROLLMENT_SECRET"
```

## Endpoints

- `GET /health` — Health check (no auth)
- `POST /v1/auth/device` — Issue device token (`ENROLLMENT_SECRET`)
- `POST /v1/auth/device/rotate` — Rotate current device token
- `POST /v1/auth/device/revoke` — Revoke current device token
- `GET /v1/usage` — Usage summary (device token)
- `POST /v1/outfit/generate` — Generate outfit (device token)
- `POST /v1/outfit/alternatives` — Swap alternatives (device token)

## Auth

Content requests require a per-device Bearer token:

```
Authorization: Bearer <device-token>
```

A legacy shared `DEVICE_TOKEN` secret is honoured only when that secret is configured. Leave it
unset (or delete it) to disable that path.

## Spend cap (sample values)

`src/types.ts` ships **illustrative defaults** (`dailyCapUSD: 1.0`, `softThresholdUSD: 0.5`).
They are not recommendations. Override them with plain-text vars in your local config:

```toml
[vars]
DAILY_CAP_USD = "1.00"
SOFT_THRESHOLD_USD = "0.50"
```

Invalid or non-positive values fall back to the defaults; the soft threshold is clamped to the cap.
Optional `ATTRIBUTION_URL` sets the `HTTP-Referer` sent to the model provider (default
`https://example.invalid`).

## Development

```bash
npm ci          # lockfile required (CI + local)
npm run typecheck
npm test
npm run dev     # wrangler dev --config wrangler.local.toml (needs the local config above)
```

`npm run typecheck` must pass: `tsconfig.json` includes Node types so Stage 3 `node:crypto` / `Buffer` (via `file:../outfit-engine`) and Workers auth crypto resolve. CI runs the same commands in `backend-ci.yml` → `workers-checks`.

## Architecture

- **Platform:** Cloudflare Workers
- **Auth:** Per-device opaque tokens (hashed in per-device Durable Objects)
- **Storage:** KV for usage ledger; transactional SQLite Durable Objects for token registry (hashes only)
- **Spend cap:** ledger + configurable cap/threshold helpers (see above); no model-call path exists yet, so nothing is enforced against real spend
- **Path:** Deterministic only (no model calls yet)
- **Privacy:** fail-closed provider data collection (`provider.data_collection: deny`)
