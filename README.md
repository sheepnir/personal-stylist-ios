# Personal Stylist

Personal Stylist is a local-first iOS app for getting more out of the clothes you
already own. The core loop is: **wardrobe → outfit → swap → wear → cost-per-wear**.
You pick an anchor garment, the app builds an outfit around it, you can swap any
slot for a ranked alternative, and logging "wearing this" feeds wear history and
cost-per-wear.

> **Rights:** all rights reserved by the copyright holder named in [NOTICE.md](NOTICE.md).
> This repository is published for reference only; no licence to reuse the code is granted.

## Status

Early-stage, single-developer project. The deterministic core loop runs end to end
in the iOS Simulator against synthetic fixtures. Model-backed features described in
`docs/openapi.yaml` (endpoints marked `x-milestone: M2`) are specified but not built.
Nothing here is presented as production-ready.

## Architecture

- **Local-first.** The device is the source of truth (SwiftData). The backend holds
  no wardrobe or outfit content — only device-token auth, a provider proxy, and a
  usage ledger.
- **Deterministic engine.** A four-stage pipeline (hard filter → scoring/shortlist →
  builder → validator) written as pure TypeScript functions with no network access.
  The same engine is served by a local HTTP bridge for the Simulator and by a
  Cloudflare Worker for devices.
- **One contract.** The bridge and the Worker implement `docs/openapi.yaml`:
  `GET /health`, `POST /v1/outfit/generate`, `POST /v1/outfit/alternatives`.
- **Images stay on the device.** Anything that would send an image off-device is
  fail-closed.
- **Secrets never ship in the app bundle.** Device tokens live in the Keychain;
  nothing secret is written to `Info.plist` or xcconfig.

## Codebase map

| Path | What lives there |
|---|---|
| `project.yml` | XcodeGen spec — source of truth for `PersonalStylist.xcodeproj` (iOS 17, Swift 5.9) |
| `App/` | App entry (SwiftData container + fixture seed), core-loop state, engine client, engine URL config, Keychain token store |
| `Features/` | SwiftUI screens per loop step: `Wardrobe`, `Review`, `Board`, `Swap`, `Wear`, `Profile` |
| `Design/` | Display tokens and user-facing copy helpers |
| `Persistence/` | `PersistenceStore` protocol + DTOs the UI uses; `SwiftData/` is the real store |
| `Tests/`, `UITests/` | XCTest targets (UI tests are opt-in, not run in CI) |
| `backend/outfit-engine/` | Deterministic Stage 1–4 engine, eval harness, local HTTP bridge on `127.0.0.1:8787` |
| `backend/workers/` | Cloudflare Worker: Bearer device-token auth, KV usage ledger, serves the engine |
| `fixtures/` | Synthetic wardrobe, one synthetic sample persona (profile seed + scenario profiles), and evaluation scenarios — shared by the iOS bundle, engine tests, and eval |
| `docs/` | `openapi.yaml` (API contract), `demo-local.md` (Simulator runbook), `garment-photo-reference.md` |
| `scripts/` | Repository checks run by CI, plus local config helper |

All fixture data is synthetic: generated SVG placeholders, generic garment names, and
an invented sample persona. There are no real photographs or personal data.

**Terminology.** In the code, "founder profile" (`FounderProfileSeedLoader`,
`fixtures/profile/founder-seed.json`, `check-no-founder-literals.sh`) is the app's term for the
*primary user's* style profile — the first profile a fresh install is seeded with. The seed
shipped here is the synthetic sample persona; the names are kept only to avoid an invasive rename.

## Build and test

### Engine

```bash
cd backend/outfit-engine
npm ci
npm run typecheck
npm test            # vitest run — do not run bare `vitest` (watch mode)
npm run eval -- run --models deterministic --scenarios all --repeats 2
npm run serve:local # bridge on http://127.0.0.1:8787; Simulator generate/swap needs it running
```

### Workers

```bash
cd backend/workers
npm ci
npm run typecheck
npm test
```

### iOS

Requires Xcode with an iOS 17+ Simulator and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
xcodegen generate   # after adding/removing/moving sources or editing project.yml
xcodebuild test -project PersonalStylist.xcodeproj -scheme PersonalStylist \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  CODE_SIGNING_ALLOWED=NO -only-testing:PersonalStylistTests
```

If `xcodebuild` reports that the active developer directory is the Command Line
Tools, prefix the command with
`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

See `docs/demo-local.md` for the Simulator demo runbook and launch arguments.

### Release build numbers

Build numbers follow `YYYYMMDDNN`: the date plus a two-digit counter for builds made on
that day (for example, the first build on 26 September 2026 is `2026092601`). Every
distributed build must use a number strictly greater than the last distributed one, or
the upload is rejected as not newer. The value lives in `project.yml` as
`CURRENT_PROJECT_VERSION`; run `xcodegen generate` after changing it and commit the
regenerated project. `MARKETING_VERSION` (currently `0.1.0`) is the user-visible version
and changes independently.

A release build also needs the untracked local configuration described under
[Local configuration (untracked)](#local-configuration-untracked): the bundle identifier
of the distribution record and the signing team.

### Repository checks

```bash
./scripts/check-no-founder-literals.sh           # sample wardrobe garment names must not be hard-coded in Swift sources
python3 scripts/check-wear-logging.py
python3 scripts/check-asset-library.py
python3 scripts/verify-cost-per-wear-copy.py
python3 scripts/verify-generate-failure-copy.py
python3 scripts/verify-openapi-contract-examples.py   # needs `pip install jsonschema pyyaml`
npx @redocly/cli@2.53.3 lint docs/openapi.yaml
```

## Local configuration (untracked)

The repository ships placeholders only. Supply your own values through files that
are gitignored:

| What | Where | Notes |
|---|---|---|
| Apple Team ID | `Config/LocalSecrets.xcconfig` → `DEVELOPMENT_TEAM = <TEAMID>` | Only needed to run on a device. Simulator builds work without it. |
| Bundle identifier | `Config/LocalSecrets.xcconfig` → `PRODUCT_BUNDLE_IDENTIFIER = <your bundle id>` | Tracked default is `com.example.PersonalStylist`, set in `Config/Debug.xcconfig` / `Config/Release.xcconfig` (not in `project.yml`, so no `xcodegen generate` is needed to override it). A release build must use the identifier of its App Store Connect record; the value must match `^[A-Za-z0-9.-]+$` or the script refuses it. The Keychain service for the device token follows it (`<bundle id>.device-token`). A build that stored its token under the earlier fixed service (`com.example.PersonalStylist.device-token`) is migrated on first load: the item is copied to the derived service, then the old item is deleted. |
| Worker URL | `Config/LocalSecrets.xcconfig` → `OUTFIT_ENGINE_BASE_URL = https:/$()/<your-worker-host>` | xcconfig needs `//` escaped as `/$()/`. `scripts/sync-local-secrets.sh` writes this file for you. Tracked defaults: **Debug ships an empty URL** (Simulator → local bridge `127.0.0.1:8787`; a device falls back to the compiled placeholder), Release ships the placeholder `stylist-backend.example.invalid`. |
| Worker name, KV / rate-limit ids, environments | gitignored `backend/workers/wrangler.local.toml` | The committed `wrangler.toml` is a sample only. The single recipe is in `backend/workers/README.md` ("Configure and run wrangler"). This repository ships no deployment automation. |
| Worker secrets | `wrangler secret put` — see the same recipe | Never stored in the repo; per environment. For `wrangler dev`, use an untracked `.dev.vars`. |
| Spend cap, attribution URL | Worker vars `DAILY_CAP_USD`, `SOFT_THRESHOLD_USD`, `ATTRIBUTION_URL` | The values in `backend/workers/src/types.ts` are illustrative samples, not recommendations. See `backend/workers/README.md`. |
| Device token (Debug) | Xcode scheme environment variables `DEVICE_TOKEN` or `ENROLLMENT_SECRET` | Stored in the Keychain at runtime; never written to `Info.plist`. |

`Config/LocalSecrets.xcconfig.example` shows the expected shape. The Simulator demo
needs none of this: a Debug build with no `LocalSecrets.xcconfig` has an empty
`OUTFIT_ENGINE_BASE_URL`, so `EngineConfig` falls through to the local bridge on
`127.0.0.1:8787`, which needs no token. (If you created `LocalSecrets.xcconfig`, the Simulator
uses that URL instead; pass `-outfitEngineBaseURL http://127.0.0.1:8787` to force the bridge.)

## Notes on references in the code

Comments and the OpenAPI description cite identifiers such as `PRD §…`, `D-nn`, and
`#nnn`, and milestone ids such as `M0-nn`. These refer to internal planning documents and an
issue tracker that are not part of this repository; they are kept only as stable labels.
