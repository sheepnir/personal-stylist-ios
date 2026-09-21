# Local demo (simulator + deterministic engine)

Short runbook for the M0/M1 fixture loop on a Mac. **No OpenRouter, no Apple Developer account, no personal photos.**

## Prerequisites

- Xcode with an iOS 17+ Simulator (e.g. iPhone 17)
- Node ≥ 20 (`node -v`)
- Project at `PersonalStylist/` (XcodeGen: `xcodegen generate` if the `.xcodeproj` is missing)

## 1. Start the local generate bridge

```bash
cd backend/outfit-engine
npm install
npm run serve:local
```

- Listens on **`http://127.0.0.1:8787`** only
- Health: `curl -sS http://127.0.0.1:8787/health` → `{"status":"ok","ok":true,"mode":"deterministic-local"}`
- Contract: `docs/openapi.yaml`

Leave this terminal running while you demo.

## 2. Build & run the iOS app

```bash
cd ../..   # repo root
xcodegen generate   # if needed
xcodebuild -scheme PersonalStylist \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath ~/Library/Developer/Xcode/DerivedData/PersonalStylist-local \
  build
```

Or open `PersonalStylist.xcodeproj` in Xcode and Run (⌘R) on a simulator.

App Transport allows local networking (`NSAllowsLocalNetworking`) so the sim can reach `127.0.0.1:8787`.

A fresh checkout needs no engine configuration: `Config/Debug.xcconfig` ships an empty
`OUTFIT_ENGINE_BASE_URL`, so in the Simulator `EngineConfig` falls back to the local bridge.
If you created `Config/LocalSecrets.xcconfig`, that URL wins — pass
`-outfitEngineBaseURL http://127.0.0.1:8787` to force the bridge.

## 3. Useful launch arguments

Pass under Product → Scheme → Arguments, or via `simctl launch …`:

| Arg | Effect |
|-----|--------|
| *(none)* | Wardrobe grid (fixtures) |
| `-demoDetail` | Garment detail (prefers a set member) |
| `-demoEngine` / `-demoBoard` | Build outfit via local engine → Board |
| `-demoSort` | Wardrobe sorted “Longest since worn” |
| `-demoFilters` | Filters chrome |
| `-demoOffline` | Offline cached/stub board path |
| `-demoProfile` | Style profile draft (synthetic sample seed) |
| `-demoChangeAnchor` | Change anchor clears locks + rebuild |
| `-demoLocks` | Board after lock + try-another |
| `-demoSwap` | Board + swap sheet via `:8787` `/v1/outfit/alternatives` |
| `-demoWear` | Board → wear confirm |

Example:

```bash
xcrun simctl launch booted com.example.PersonalStylist -demoEngine
```

Board status should read something like: `Board ready (DETERMINISTIC · local :8787)`.

## 4. Core loop to click through

1. Confirm or edit the **style profile** draft (toolbar Profile) — generation expects `confirmedAt` in the normal path.
2. **Wardrobe** → tap a READY + Available garment → **Build an outfit around this**.
3. **Board** — engine assignments / gaps; Try another; Swap; Wearing this.

## Notes

- Fixtures live under `fixtures/wardrobe/` and `fixtures/profile/` (bundled into the app). Do not commit secrets or real personal photos.
- Demo availability / last-worn stamps live in fixture JSON — the app does **not** overwrite SwiftData on every launch (GH #11).
- Online Build uses S1→S2→builder→validator on localhost; Swap uses `POST /v1/outfit/alternatives`.
- Offline keeps cached/stub outfit and blocks swap (D-33).
- Draft garments are stripped from generate payloads (D-23).

## Persistence (M0-11)

App launches with a **local SwiftData** store (`PersonalStylistLocal`). On first launch it seeds garments/sets from bundled fixtures. Profile, outfits, and wear events persist across launches. UI still uses Stub DTOs mapped through `SwiftDataPersistenceStore`. Status: **DEMO** (Simulator), not verified on a device.

## Fixtures (single source)

iOS `project.yml` points at `fixtures/` directly — there is no duplicate `Resources/wardrobe` copy. Run `scripts/check-no-founder-literals.sh` to confirm no sample wardrobe garment names are hard-coded in Swift sources.

## Device / public HTTPS engine

For physical-device generate (not simulator localhost):

- Set `OUTFIT_ENGINE_BASE_URL` via scheme env, Info.plist, or launch arg `-outfitEngineBaseURL https://…`
- Device token (D-46): stored in Keychain via `DeviceTokenStore` and sent as `Authorization: Bearer …`. Never baked into Info.plist / the IPA.
- ATS keeps `NSAllowsLocalNetworking` for the local bridge; HTTPS backends do not need ATS exceptions.

### Write local config (untracked)

```bash
OUTFIT_ENGINE_BASE_URL=https://<your-worker-host> ./scripts/sync-local-secrets.sh
```

Writes gitignored `Config/LocalSecrets.xcconfig` from the `OUTFIT_ENGINE_BASE_URL` environment variable (engine base URL, optionally `DEVELOPMENT_TEAM`). **Do not put `DEVICE_TOKEN` in xcconfig** (D-46 / #168) — it would bake into Info.plist. For Debug Simulator, set Xcode scheme Environment Variables:

- `DEVICE_TOKEN` — existing opaque token → Keychain seed, or
- `ENROLLMENT_SECRET` — Debug auto-enrolls via `POST /v1/auth/device` against the HTTPS Worker.

**Release builds:** Debug env bootstrap is compiled out. Use **Style profile → Device access** to paste an enrollment secret once (or an issued device token). Do **not** rely on Debug→Release Keychain continuity as the primary path.

Local `:8787` bridge needs no token.
