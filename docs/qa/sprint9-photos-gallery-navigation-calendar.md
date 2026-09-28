# Sprint 9 QA — photo editing, wearing gallery, bottom tabs, wear calendar

Scope and design: [ADR-0004](../architect/decisions/0004-sprint9-photos-gallery-navigation-calendar.md). Epic #118. Engineering evidence only; device acceptance is recorded privately.

## What each check proves

| Area | Automated evidence | Where |
|---|---|---|
| Gallery persistence, schema V3 | Ordering and tie-break, more than five photos, idempotent and concurrent adds, rollback on failed write/fsync/commit, crop keeps `addedAt` and source, remove scope, garment delete and clear, stale save after deletion, camera-only export state, relaunch, orphan sweep and its empty-table guard | `Tests/WearingPhotoPersistTests.swift` |
| Upgrade (synthetic store) | A populated V2-stamped, Sprint 8-shaped store keeps every semantic row over three V3 opens: garments, ids, prices, currency, primary photo URIs, sets, outfit, active and voided wears, memberships, profile version, index rows; an unversioned store also opens | `Tests/Sprint9SchemaMigrationTests.swift` |
| Upgrade (installed app) | Baseline build installed on a fresh Simulator, populated, then the new build installed in place; rows, photo hashes and the clean-start key compared, plus a second relaunch | `scripts/verify-sprint9-upgrade.sh`, workflow "Upgrade install (Simulator)" |
| Calendar | Local-day grouping identical to `WearLogging`: midnight, time-zone change, DST forward/back and a midnight gap, leap day, month/year boundaries, first weekday, voided and legacy multi-event days, confirm/duplicate/replace/Undo; stored membership survives later board changes; hosting the calendar writes nothing | `Tests/WearCalendarTests.swift`, `Tests/WearCalendarWearLoggingTests.swift`, `Tests/Sprint9QATests.swift` |
| Tabs | Tab-change policy; board under the tab shell never generates on appear; leaving Profile keeps edits unsaved until an explicit Save; Discard restores saved values without writing | `Tests/TabNavigationTests.swift`, `Tests/TabShellHostedTests.swift` |
| Crop | Geometry (portrait, landscape, clamp, no-op); EXIF rotation and mirroring; camera orientation; bounded large input; profile source retention without re-encoding; legacy profile picture becomes the source; garment crop through the staged replace with source lineage; failure keeps the current photo; source sweep | `Tests/CropGeometryTests.swift`, `Tests/PhotoCropTests.swift` |
| Gallery and selfie session | Latest-first with five previews; repeated Save makes one item; export sends the exact confirmed bytes; denied/failed export keeps the local photo and never claims success; retries never add items; concurrent taps export once; library imports never export; gallery actions never change wear counts | `Tests/WearingGallerySessionTests.swift` |
| Provider boundary | Garment DTO carries no gallery fields; the real generate and alternatives request bodies carry no gallery ids, photo paths or pixels; Info.plist asks for add-only Photos access and never read access | `Tests/WearingPhotoPersistTests.swift`, `Tests/Sprint9QATests.swift`, `Tests/PhotoReplaceCopyTests.swift` |
| Low storage | Out-of-space errors map to calm copy with no machine tokens | `Tests/Sprint9QATests.swift` |

## Not verified by automation

- Real camera capture (front/rear, orientation, mirroring), the add-only Photos prompt and export, and denied-permission recovery need a physical device. Simulator placeholders and injected callbacks are not device proof.
- Touch, scrolling, small-phone layout, large text and the keyboard next to the tab bar need Simulator and device passes.
- Visual quality of crops on real photos.

## Background removal

Carried over (#125). The only candidate is the iOS 17 on-device foreground-instance mask. Its cut-out quality on garments (light/dark backgrounds, low contrast, sleeves, shoes, fine edges) must be judged on a supported device, and the JPEG-only reference contract needs a decided composited background before any cut-out can be stored. Neither could be established in this sprint, so nothing ships and the issue stays open.

## Phone acceptance pass (concise)

1. Tabs: Wardrobe, Outfit, Calendar, Profile all reachable; opening Outfit with no outfit shows the empty state and does not generate.
2. Build from a garment, Try another, Swap, Keep, Wear, Change starting item and Cancel still work; Jev/Luna labels unchanged.
3. Edit Profile, switch tab: Save / Discard / Keep editing appears.
4. Crop the profile picture and a garment reference photo; Cancel leaves them unchanged.
5. Garment → Add wearing photo → Take selfie (front camera, switch works) → Crop → Save to Photos on → Save: photo appears first and a copy is in Photos. Repeat with Photos access denied: photo stays in the app, message says it was not saved to Photos, Retry works after enabling access.
6. Add more than six photos; View all shows every photo; remove one with confirmation.
7. Calendar: today shows the logged look; an empty day says "No outfit recorded"; a garment opens its detail.
