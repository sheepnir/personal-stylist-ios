# Garment background-removal feasibility

Status: deferred from shipped behavior; physical-device quality and support gate pending.
No app target, UI, storage schema, or network path is changed by this probe.

Candidate: Apple's `VNGenerateForegroundInstanceMaskRequest` (iOS 17 / macOS 14).
It estimates foreground instances, not garment identity. Multiple instances are ambiguous;
zero instances, processing failures, unsupported execution and cancellation must preserve
the current photo. A single instance may still include a person, background or wrong object:
instance count alone does not establish acceptable garment segmentation.

Official references to verify on a Mac with access:

- https://developer.apple.com/documentation/vision/vngenerateforegroundinstancemaskrequest
- https://developer.apple.com/documentation/vision/vninstancemaskobservation
- https://developer.apple.com/videos/play/wwdc2023/10176/

The cloud pass could not read the current official documentation: public documentation and
JSON documentation endpoints returned HTTP 403 with TLS verification enabled. API signatures
and current supported-device behavior therefore remain an explicit Mac verification gate.
No Swift/Xcode toolchain or physical device is available in this Linux environment.

## Standalone probe

`scripts/probe-foreground-mask.swift` is outside all XcodeGen target source roots. It takes
a synthetic input and a new output path, normalizes orientation and bounds the long edge
to 1600 pixels, requests a mask, refuses zero or multiple instances, composites on fixed
solid `#F2F2F2`, and encodes JPEG at 0.82 quality without source metadata. It preserves
the full canvas and refuses to overwrite an existing file. It is an uncompiled handoff
probe, not an implementation or device-support guarantee. Its self-test covers selection
policy only; it does not mock or validate Apple's segmentation.

On macOS 14+ with Xcode selected:

```sh
cd personal-stylist-ios
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift scripts/probe-foreground-mask.swift --self-test
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift scripts/probe-foreground-mask.swift /tmp/synthetic-input.jpg /tmp/synthetic-candidate.jpg
```

Record compiler diagnostics, API-documentation checks and visual results before changing
the probe. A Mac result does not pass the iPhone gate. This command is synchronous and
has no responsive in-app cancel control; terminate the process to stop the command.

## Synthetic matrix and device gate

Every row is **not run** in the cloud pass. Prepare synthetic images locally; no personal
photos, device identifiers or operational records belong in this public repository.

| Input | Required inspection |
|---|---|
| Light garment / light background | Missing fabric, contrast failures, halos |
| Dark fabric / dark background | Lost dark edges and retained background |
| Sleeved garment | Both sleeves, cuffs, holes and interior openings |
| Single shoe and shoe pair | Full shapes; refuse multi-instance ambiguity |
| Patterned fabric | Pattern preserved; no holes within fabric |
| Fine edges, lace and straps | Lost edges, halos and unwanted fill |
| Multiple plausible objects | No automatic choice; current picture unchanged |
| Empty or undecodable input | Safe refusal; current picture unchanged |
| Synthetic garment on person | Never imply garment-only recognition |

Mac owner must first verify current Apple API availability and execution restrictions,
compile the probe, and run the selection self-test and matrix. A concrete standalone iOS
harness now lives under `scripts/foreground-mask-harness/`; it is excluded from the production
project source roots and has its own XcodeGen project and mock-test target. It uses ImageIO
orientation normalization and the 1600 px bound, a serial worker, cooperative Vision request
cancellation and source-generation tokens to reject late results. While cancelling, Run
remains disabled until the worker actually completes. Changing source or crop invalidates
the candidate. Masking occurs on the full normalized source before both source and mask
receive the same optional 10% crop. Preview and Restore preview are in-memory only.

```sh
cd personal-stylist-ios
./scripts/foreground-mask-harness/run-mac.sh
# If that Simulator is unavailable, substitute an installed destination:
HARNESS_DESTINATION='platform=iOS Simulator,name=iPhone 16' ./scripts/foreground-mask-harness/run-mac.sh
# Open ForegroundMaskHarness.xcodeproj in the fresh directory printed by the wrapper.
```

The wrapper copies the harness to a fresh temporary directory, generates that isolated
project and builds/tests unsigned on Simulator. It prints the directory and retains the
build log and fresh xcresult there. Existing local signing edits are never overwritten.
Copy evidence to private durable storage before temporary-directory cleanup.
It requires XcodeGen and an installed Simulator; use `xcrun simctl list devices available`
to select a destination. It does not select a signing team or touch production configuration.
In Xcode, choose the harness app target, set a local signing team and unique bundle id as
needed, select the supported attached iPhone, and Run. No camera/Photos permissions, network
access, gallery/profile storage, production model import or app-owned file writes are present.
Use Run, Cancel, sample changes during processing, Restore preview, crop and light/dark surround
to inspect behavior. Mock tests cover success, empty/ambiguous/error, repeated Run,
cancellation with late success, and source-change stale results; all remain unrun in cloud.

Built-in programmatic drawings cover controlled shape/contrast policy probes only. They are
insufficient to establish real photo-quality behavior. Before accepting the feature, locally
add synthetic photographic garment inputs to this standalone harness (a local bundle fixture
only; no personal photos or permission/import flow), and include the matrix above, mirrored/
rotated orientation cases and synthetic garment-on-person refusal expectations. The current
harness has no garment classifier; a singleton person must never be called garment-only.

Do not enable the production app feature to test feasibility. Run each matrix row repeatedly, inspect
original/candidate side by side and against light/dark UI backgrounds, measure wall time
and memory with Instruments, and record device/OS privately. Target: 1600 px finishes
within five seconds, with immediately responsive cancel; this is not an Apple guarantee.
If the gate cannot pass within the bounded feasibility window, retain this deferral.

Before integration, test worker-thread processing with one request at a time; cancellation
must cancel the Vision request where supported and invalidate results so late completion
cannot publish or save. Release masks, pixel buffers and CI intermediates after each run.
Simulator or Mac timings cannot establish phone responsiveness or memory safety.

## Integration contract after acceptance only

Order: retained bounded original → normalize orientation → generate mask in full normalized
source coordinates → apply the same selected crop to source and mask → composite fixed
neutral background → JPEG candidate → explicit preview/Save. A source change invalidates
the mask; crop changes re-render both with the same pixel rectangle. Never mix coordinates
from cropped and uncropped images, and never re-edit the flattened JPEG when a source exists.

Current `cropGarmentPhoto` stages a new displayed JPEG, writes unchanged app-held source
bytes for that staging UUID, commits `imagePath` and primary `originalURI` together, then
cleans up superseded owned files. Keep this D-74 contract, source protection/backup exclusion,
and owner-specific cleanup. Do not repurpose `processedURI`. Restore stages the retained
original as another candidate and requires explicit Save. Preview, Cancel, failure and stale
results write nothing; old display/source stay valid on write/save failure. No profile or
wearing-photo processing, photo-network DTOs, transparent export, selection UI or cloud fallback.
