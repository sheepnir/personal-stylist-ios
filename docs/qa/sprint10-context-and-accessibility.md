# Sprint 10 context and accessibility QA

Implementation contract: ADR-0005. This checklist contains synthetic/local verification only. No physical-device or XCTest result is implied by its presence.

## Automated checks to run on macOS

Run the full `PersonalStylistTests` target. Added coverage in existing target files:

- `ManualContextPreferencesTests` in StylingModelTests: missing/corrupt/old preferences preserve stored bytes, independent unknown-enum fallback, local midnight/time-zone changes, model recreation and same-value confirmation without generation.
- OutfitEngineClientStubTests: edits leave current outfit/provenance intact and make no requests, delayed generate rejected with explicit retry using new context, delayed swap rejected after changing away and back, underlying transport cancellation observed, offline cache keeps the context reminder.
- CropGeometryTests: gesture-free positioning reaches real edge crops, round-trips using the same clamp as dragging/Save, handles unavailable axes and nonfinite values.

Use isolated defaults and synthetic URLProtocol fixtures only. Run full tests to detect interference with existing provider/consent/auth/cancel/fallback controls. Linux repository/backend checks cannot establish iOS compilation or test execution.

## Device walkthrough (pending)

1. Start with retained wardrobe/profile/reference/gallery/history. Change occasion, temperature and rain; editing must not make a request or relabel the current outfit. Relaunch; choices remain. Confirm same choices for today without generating. Check next-day last-used reminder and local time-zone changes.
2. Generate explicitly and confirm request uses chosen context. Change context during generate, then during Swap, including changing away and back. Prior outfit/provenance remains, late success/failure stays discarded, retry remains explicit. Check failure, Cancel, return and offline behavior. Provider selection and consent remain unchanged.
3. VoiceOver: each board action remains separate; context disclosure, occasion/temperature pickers, Rain and confirmation have human-readable labels and selection state. Verify focus on dismissal/error and no repetitive announcements.
4. Crop: use Zoom, Horizontal position and Vertical position without drag/pinch. Reach meaningful edge crops; verify Save reflects preview, Reset centres, untouched Save and Cancel preserve bytes. At largest accessibility text sizes, shape/position/reset controls scroll and toolbar Save/Cancel remain reachable.
5. Calendar: selected date has non-color border and selected trait. At accessibility sizes, navigate full-date list; selected-day detail precedes the list. On a narrow phone, standard grid scrolls horizontally when necessary to retain at least 44 pt day targets. Month navigation and garment drill-down remain read-only.
6. Gallery/camera: meaningful photo labels, crop/remove and crop/retake stack at accessibility sizes; verify confirmation, local save, add-only Photos success/denial/retry without duplicates and focus recovery. No new permissions.
7. Tabs and unsaved Profile leave guard preserve existing stacks and edits. Reduce Motion avoids board lock animation. No tab/day/gallery browsing generates or logs a wear.

Record pass/fail and reproduction steps for each device area privately. Snapshot/hosted type tests alone do not establish VoiceOver or text-size usability. Keep device-dependent acceptance open until completed.
