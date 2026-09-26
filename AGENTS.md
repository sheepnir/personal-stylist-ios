# AGENTS.md — Personal Stylist

Engineering guide for anyone (human or coding assistant) working in this repo.
`CLAUDE.md` and `agent.md` are symlinks to this file — edit `AGENTS.md` only.

## Public repository rules

This repository is **public**. Everything committed here — and every issue, pull-request
description, review comment, commit message, and CI log — is public and effectively permanent.

- **Never write operational or security records here:** release / TestFlight / App Store Connect
  records, live-backend hostnames or ids, security reviews of a deployed service, budgets,
  personal data, real photos, or links to agent sessions. Those belong in the owner's private
  records, not in this repository.
- **Secrets only via untracked local config** (see "Architecture principles"). Never paste a
  secret into a file, commit message, issue, or CI log.
- **Commits must use a GitHub noreply identity.** Pushes that would expose a personal email
  address are rejected by the account.
- Fixtures stay synthetic; placeholders (`example.invalid`, `com.example.*`, `REPLACE_WITH_…`)
  stay placeholders in tracked files.

## Project

Personal Stylist (iOS) — local-first wardrobe → outfit → swap → wear → cost-per-wear.
See `README.md` for the overview and `NOTICE.md` for rights.

Reference docs: `docs/openapi.yaml` (API contract), `docs/demo-local.md` (Simulator
demo runbook + launch args), `docs/garment-photo-reference.md`.

## Architecture principles (locked)

- **Local-first.** The device is the source of truth (SwiftData). The backend holds no
  wardrobe/outfit user content — auth, provider proxy, and usage ledger only.
- **Core loop first.** Do not add features outside wardrobe → outfit → swap → wear
  without an agreed plan.
- **Secrets stay out of the repo and out of the app bundle.** Local values live in
  untracked files (`Config/LocalSecrets.xcconfig`, `.dev.vars`, `.env`). Never print or
  commit them. Device tokens belong in the Keychain, never in `Info.plist` or xcconfig.
- **Images off-device are fail-closed.** No provider image sends without an explicit
  privacy path.

## Codebase map

| Path | What lives there |
|---|---|
| `project.yml` | XcodeGen spec — source of truth for `PersonalStylist.xcodeproj` (iOS 17, Swift 5.9) |
| `App/` | `PersonalStylistApp` (entry: SwiftData container + fixture seed), `LoopDemoModel` (core-loop state), `OutfitEngineClient`, `EngineConfig`, `DeviceTokenStore` (Keychain) |
| `Features/` | SwiftUI screens per loop step: `Wardrobe`, `Review`, `Board`, `Swap`, `Wear`, `Profile` |
| `Design/` | Display tokens and user-facing copy helpers (`DressingCopy`, `CostPerWearCopy`, `AvailabilityToken`) |
| `Persistence/` | `PersistenceStore` protocol + Stub DTOs the UI uses; `SwiftData/` is the real store (`PersonalStylistLocal`), mapped via `StubEntityMapper` |
| `Tests/` | XCTest target `PersonalStylistTests` |
| `backend/outfit-engine/` | Deterministic Stage 1–4 engine (TypeScript, pure functions, no network), eval harness, local HTTP bridge on `127.0.0.1:8787` |
| `backend/workers/` | Cloudflare Worker: Bearer device-token auth, KV usage ledger, serves the engine (`file:../outfit-engine`) |
| `fixtures/` | Synthetic wardrobe, synthetic sample profile, evaluation scenarios — shared by the iOS bundle, engine tests, and eval |

The local bridge and the Worker serve the same contract (`docs/openapi.yaml`):
`GET /health`, `POST /v1/outfit/generate`, `POST /v1/outfit/alternatives`.

## Commands

Engine — exactly what CI runs:

```bash
cd backend/outfit-engine
npm ci
npm run typecheck
npm test            # vitest run — never bare `vitest` (watch mode hangs agents)
npm run eval -- run --models deterministic --scenarios all --repeats 2
npm run serve:local # bridge on http://127.0.0.1:8787; Simulator generate/swap needs it running
```

Workers:

```bash
cd backend/workers
npm ci
npm run typecheck
npm test
```

iOS — if `xcodebuild` says the active developer directory is CommandLineTools, set
`DEVELOPER_DIR`; no sudo or `xcode-select -s` needed:

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodegen generate   # after adding/removing/moving sources or editing project.yml
xcodebuild test -project PersonalStylist.xcodeproj -scheme PersonalStylist \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  CODE_SIGNING_ALLOWED=NO -only-testing:PersonalStylistTests
```

Repo checks — from the repo root, non-zero exit on failure:

```bash
./scripts/check-no-founder-literals.sh           # no sample wardrobe garment names in Swift sources
python3 scripts/check-wear-logging.py            # wear-logging rules (mirrors Persistence/StubModels.swift)
python3 scripts/check-asset-library.py           # asset catalog naming + light/dark coverage
python3 scripts/verify-cost-per-wear-copy.py     # cost-per-wear copy cases
python3 scripts/verify-generate-failure-copy.py  # no raw HTTP/URL errors in the board UI
python3 scripts/verify-openapi-contract-examples.py
npx @redocly/cli@2.53.3 lint docs/openapi.yaml   # same lint as CI
```

## Cursor Cloud specific instructions

Cloud agents run on Linux with no Xcode. You can edit Swift but cannot run XcodeGen,
`xcodebuild`, or the Simulator. iOS verification happens only in macOS CI (iOS CI workflow).
Say so in the PR instead of claiming iOS results.

The environment (`.cursor/environment.json`) provides Node 22, `npm ci` in both backend
packages, a global `redocly`, and a Python venv at `$HOME/.venvs/ps-ci` with the hash-pinned
CI dependencies. Never add secrets to the environment or its Build. Never run
`wrangler deploy` or any wrangler command against a real account.

Verification commands (run from the repo root; no extra install step after a successful
environment Build):

```bash
node -v && npm -v && redocly --version && python3 --version
(cd backend/outfit-engine && npm ci && npm run typecheck && npm test \
  && CI=true npm run eval -- run --models deterministic --scenarios all --repeats 2 \
  && CI=true LATENCY_REPEATS=5 npm run latency:gate)
(cd backend/workers && npm ci 2>&1 | tee /tmp/workers-npm-ci.log && npm run typecheck && npm test)
! grep -q EBADENGINE /tmp/workers-npm-ci.log
(cd backend/workers && npm ls wrangler workerd)
redocly lint docs/openapi.yaml --format=stylish
./scripts/check-no-founder-literals.sh
python3 scripts/check-wear-logging.py
python3 scripts/verify-cost-per-wear-copy.py
python3 scripts/verify-generate-failure-copy.py
python3 scripts/check-image-guard-parity.py
python3 scripts/check-asset-library.py
"$HOME/.venvs/ps-ci/bin/python" scripts/verify-openapi-contract-examples.py
```

## Gotchas

- **CI:** four workflows under `.github/workflows/` — backend (engine + Workers + OpenAPI
  lint, path-filtered), iOS (XcodeGen + `xcodebuild test` on a macOS runner, path-filtered;
  UI tests are opt-in and not in CI), repo checks (every PR), asset-library check. A green
  engine job says nothing about iOS — check the iOS workflow when Swift changes.
- **Workers typecheck** needs `@types/node` and `"types": [..., "node"]` in
  `backend/workers/tsconfig.json` because the linked engine Stage 3 (and Workers auth)
  import `node:crypto` / `Buffer`. Do not drop those types to "fix" Workers-only typing.
- **`PersonalStylist.xcodeproj` is generated but tracked.** Don't hand-edit
  `project.pbxproj`; run `xcodegen generate` and commit the result.
- **Fixtures are single-source:** `project.yml` bundles `fixtures/wardrobe/*.json` and
  `fixtures/profile/founder-seed.json` directly, so an edit changes the iOS seed *and*
  engine tests/eval. "Founder profile" is the app's term for the primary user's profile; the
  shipped seed and every scenario profile describe one synthetic sample persona. Images are
  synthetic SVGs only — never add real personal photos as fixtures.
- **Seed runs only when the store is empty:** fixture edits won't show in an
  already-seeded install — delete the app to re-seed.
- **No machine tokens in UI:** route enums and engine reasons through
  `Design/DressingCopy.swift`; never surface raw HTTP/URL errors.
- **Engine URL resolution** (`App/EngineConfig.swift`): launch arg `-outfitEngineBaseURL`
  → env `OUTFIT_ENGINE_BASE_URL` → Info.plist → Simulator `127.0.0.1:8787` / device public
  HTTPS Worker. Debug ships an empty Info.plist URL so the Simulator reaches the local bridge
  by default; the Release/compiled default host is a placeholder — override it locally.
- **xcconfig URLs** must escape `//`: `https:/$()/host…` (see `Config/Debug.xcconfig`).
- **Worker placeholders:** the Worker `name`s, KV / rate-limit ids and spend-cap values under
  `backend/workers/` are samples, and the repo ships no deployment automation. Real values go in
  the gitignored `wrangler.local.toml` (recipe: `backend/workers/README.md`).
- **Local overrides:** `DEVELOPMENT_TEAM` and `OUTFIT_ENGINE_BASE_URL` are defined in the
  xcconfigs (not in `project.yml` target settings) so the untracked
  `Config/LocalSecrets.xcconfig` can override them.

## Workflow hygiene

- **CI workflows:** every workflow declares `permissions: contents: read`, a per-PR
  `concurrency` group, `persist-credentials: false` on checkout, and actions pinned to a full
  commit SHA with a `# vX.Y.Z` comment — bump both together.

- Work on a short-lived branch and open a pull request into `main`; don't push straight to
  `main`. Squash-merge and delete the branch afterwards.
- Preserve existing files; keep changes scoped to the task.
- Claims need evidence: say what was run and what was *not* verified. Simulator results
  are not device results.
