# 0004: Sprint 9 — photo editing, wearing gallery, bottom navigation and wear calendar

Status: Accepted for implementation by the founder's Sprint 9 instruction, 2026-09-28. Upload and any deployment remain separately gated. Earlier accepted records (ADR-0001 to ADR-0003) remain unchanged.

## Scope and delivery

The founder appoints Claude Code as Sprint 9 delivery owner. This supersedes the Sprint 6 coordination window in ADR-0002 for this sprint only. Implementation, independent code review and QA stay separate passes. Each pass records the tool and revision that actually produced it and does not imply a different model family.

This sprint advances the core-loop-only scope only for the following owner-requested capabilities:

1. Crop photos inside the app.
2. Optionally remove a garment reference photo's background on device, if that is feasible (see "Background removal").
3. A "You wearing this" gallery on garment detail.
4. In-app selfie capture, with an optional copy saved to the system Photos library.
5. Persistent bottom navigation.
6. A calendar of recorded wear history.

The wardrobe → generate → swap → keep → wear loop, the Jev/Luna selection paths, consent, provenance, spending controls, prices, history and cost-per-wear are unchanged. None of these features needs a backend change or a paid request. Opening a tab, a gallery or a calendar date never calls a model.

## Product defaults

| Area | Default |
|---|---|
| Bottom tabs | Wardrobe, Outfit, Calendar, Profile. |
| Initial destination | Wardrobe. Each tab keeps its own navigation stack. Modal work is not reopened at launch. |
| Crop coverage | Profile picture, garment reference photo and wearing-gallery photos. One shared editor. Each storage contract is preserved. |
| Background removal | Optional, feasibility-gated, on device only, for garment reference photos. No cloud service. |
| Wearing gallery | The latest added photo is shown prominently, followed by up to five recent previews and a View all gallery. |
| Five pictures | An initial display count, not a storage limit. Older photos are never deleted automatically. |
| Photo association | The user explicitly chooses one garment per add flow. No automatic recognition and no multi-garment tagging. |
| Gallery ordering | Persisted `addedAt`, newest first. Ties break on `id`. Editing does not change `addedAt`. |
| Calendar | Recorded wear history only. Not a planner. |
| Calendar day grouping | The app's existing local-calendar semantics (`Calendar.current`, as used by `WearLogging`). Stored dates are never rewritten. |
| Photos export | "Save to Photos" appears on the confirmed selfie flow and starts on. Previews, cancelled captures and retakes are never exported. |
| Capture versus wear | Adding, editing or removing a photo never logs a wear or changes wear counts. Logging a wear stays an explicit action. |

## Photo ownership

Each feature owns its own storage. One feature's cleanup never touches another feature's files.

| Photo | Storage | Owner |
|---|---|---|
| Garment reference | `Documents/GarmentPhotos/{uuid}.jpg`, addressed by `GarmentEntity.imagePath = user-photo:{uuid}`. The primary `GarmentImageEntity.originalURI` mirrors it. | Unchanged `UserGarmentPhotoStore` contract. |
| Garment reference crop source | `Documents/GarmentPhotos/Sources/{uuid}.jpg`, keyed by the uuid of the displayed file it produced. | Removed together with the displayed file it belongs to. |
| Profile picture | `Application Support/ProfilePhoto/profile.jpg`, plus `profile-source.jpg` once the picture has been edited or replaced after this sprint. | `ProfilePhotoStore`. |
| Wearing photo | `Documents/WearingPhotos/{uuid}.jpg`, with a displayed file and a source file per photo. | `WearingPhotoFileStore` only. |

- `processedURI` is not repurposed. Cropping a garment reference photo writes a new displayed file through the existing staged photo-replace commit (D-74). `imagePath` and the primary `originalURI` therefore stay consistent.
- The app keeps the source it actually holds, downsampled to the existing 1600 px bound, so re-editing does not compound quality loss. It does not claim to recover the camera's native resolution. For photos that existed before this sprint, the source is the file already on disk.
- Every app-owned photo file keeps `NSFileProtectionComplete` and is excluded from backup, as before.
- No photo, thumbnail, path, file id, EXIF data or derived attribute is added to any network DTO.

## Wearing-gallery persistence (design gate)

New entity `WearingPhotoEntity`. It adds no relationship, and every existing `@Model` class is unchanged:

| Field | Purpose |
|---|---|
| `id: UUID` (unique) | Stable photo id. The add flow generates it once and reuses it on retries, so retries are idempotent. |
| `userId: UUID` | Owner, matching the other entities. |
| `garmentId: UUID` | The garment this photo shows. A plain field, not a relationship, so no existing model changes. |
| `displayFileId: UUID` | The displayed (possibly cropped) JPEG. |
| `sourceFileId: UUID?` | The app-held source used for re-editing. |
| `addedAt: Date` | Sort key, newest first. Never changed by editing. |
| `updatedAt: Date` | Last edit. |
| `sourceRaw: String` | `CAMERA` or `LIBRARY`. |
| `photosExportRaw: String?` | `SAVED`, `FAILED` or `nil` (not requested). Stored only for camera captures. |

- **Ordered fetches:** the store fetches by `garmentId` and sorts by `addedAt` descending, then by `id`. iOS 17 has no `#Index`, and a garment has few photos, so no index entity is added.
- **Add sequence:** decode, normalize orientation, downsample and crop in memory. Write the displayed and source files under new uuids. Then, in one context, check that the garment still exists, insert the row and save. If any step fails, the two new files are removed and nothing else changes. If the garment was deleted in the meantime, the save is rejected with `garmentUnavailable`.
- **Edit sequence:** the store writes a new displayed file and updates `displayFileId` and `updatedAt` in one save. It removes the previous displayed file only after that save succeeds. If the save fails, the new file is removed and the old one keeps being shown.
- **Remove sequence:** the user confirms first. The store deletes the row and saves, then removes that row's two files. Garment data, the reference photo, the profile picture, wear history and any exported Photos copy are untouched.
- **Garment deletion:** deleting a garment also deletes its gallery rows in the same save. Their files are removed afterwards. "Clear wardrobe and looks" does the same for every garment.
- **Termination between file write and commit:** after launch, a sweep removes files in `WearingPhotos/` and `GarmentPhotos/Sources/` that no row or reference points to. The sweep only looks inside those two directories, runs after the store opens, and skips files modified in the last ten minutes.

### Migration

- `PersonalStylistSchemaV3` contains the V2 models plus `WearingPhotoEntity`. The V2 → V3 stage is lightweight.
- V1, V1.1 and V2 still list the same unchanged live classes, so their checksums do not change. V3's graph is different, so no duplicate-checksum error is possible.
- Unversioned pre-#215 stores keep the existing fallback path, which now opens with the V3 schema.
- Existing garments, photo references, profile values, prices, currency, dates, sets, wear events, memberships and outfit provenance are not rewritten. No photo is re-encoded during migration.
- `baseline.2026092602.cleanStartCompleted` is unchanged.
- If the store fails to open, the existing blocked-launch screen still applies: nothing falls back to an empty or in-memory wardrobe.

## Selfie capture and Photos export

- **Camera:** the system still-photo camera opens front-facing when a front camera is available. The native switch-camera control stays available. There is no video and no microphone. Camera permission is requested only at capture time.
- **Confirm screen:** shows the garment being associated, Retake, Cancel, optional Crop and the Save to Photos toggle. The confirmed image, including any crop, is exactly what is saved.
- **Two outcomes, local first:** the gallery photo is saved locally before any Photos export. Photos access uses add-only authorization, requested only when a save to Photos is committed. Importing from Photos uses the system picker and needs no library permission.
- **Export failure:** if export is denied or fails, the local photo stays saved. The gallery offers Retry and a Settings path, and "Saved to Photos" is never shown on failure.
- **No duplicates:** Retry never creates a second gallery item. An in-flight guard stops repeated taps from exporting twice. A copy in Photos is independent: later local edits or removal do not change it.
- **Usage strings:** the camera usage description now also covers wearing photos. An add-only Photos usage description is added.

## Wear calendar semantics

- **Source of truth:** active (non-voided) wear events. Days are grouped with the same `Calendar.current` start-of-day rule as `WearLogging` and the daily-wear fetch. A time-zone change moves which local date an event falls on. Stored `wornOn` values are never rewritten.
- **One look per day:** the existing rule is preserved, including no-op reconfirmation, replacement voiding and Undo.
- **Legacy data:** if older data has several active events on one day, all of them are shown, newest first and then by `id`.
- **Membership:** the event's stored garment ids are authoritative. Later swaps do not change what the calendar says was worn. Garment deletion already removes the deleted id from events; the calendar shows the remaining pieces and never substitutes others.
- **Display metadata:** garment names and images are current display data, not historical snapshots. The calendar says so and does not claim to reconstruct an exact past photo.
- **Read-only:** browsing writes nothing, calls no model and changes no count or price. Gallery photos are not attached to past looks.

## Navigation

- A `TabView` with one `NavigationStack` per tab replaces the single stack. All four tabs share one `LoopDemoModel`, so there is exactly one current outfit.
- Building from Wardrobe or garment detail switches to Outfit and runs the existing build. Opening the Outfit tab with no outfit shows an empty state that leads back to Wardrobe and never starts a generation.
- Change starting item, Cancel and Return to outfit keep their snapshot and lock behavior and move between the Wardrobe and Outfit tabs.
- The profile editor autosaves on Back when it is pushed. As a tab root it does not autosave on disappear. Leaving the Profile tab with unsaved changes asks the user to Save, Discard or Keep editing.
- Camera, picker and crop editor are presented one at a time from the screen that owns them.
- Existing stale-result protection (generation counters and data-generation checks) keeps in-flight results off the wrong context.

## Background removal

Apple's on-device subject-lifting API for iOS 17 (`VNGenerateForegroundInstanceMaskRequest`) is the only candidate. There is no cloud fallback and no new dependency. The feature ships only if its supported-device behavior and quality can be verified on synthetic garment images covering light and dark backgrounds, low contrast, sleeves, shoes and fine edges, with the original preserved and revertible. Otherwise it is recorded as an explicit carryover with the evidence, and it is not marked complete.

## What this decision does not authorize

It does not authorize:

- a new provider or model;
- sending photos off the device;
- facial or body analysis, or automatic garment recognition;
- raising spending limits or activating the feature on more devices;
- a clean start or reseed;
- a production deployment;
- an unspecified upload.

Device acceptance stays separate from synthetic Simulator and CI evidence.
