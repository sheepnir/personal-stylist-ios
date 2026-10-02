# 0005: Sprint 10 — manual context and focused accessibility

Status: Accepted for bounded implementation by the owner's Sprint 10 kickoff, 2026-09-30. Earlier accepted decisions remain unchanged. This decision supersedes the delivery coordination window only for Sprint 10: Codex coordinates separate implementation, independent review and QA passes. Actual tools and revisions are recorded; separate agents do not imply cross-family review.

## Scope

Persist manual outfit context and improve its controls; fix concrete accessibility defects in the board, crop, gallery and calendar flows. Preserve existing navigation, photos and sources, provider choice/consent, deterministic behavior, wear history and the frozen clean-start key. Context edits never generate or log a wear. No backend changes are planned.

## Manual context (scoped revision of #23)

Store occasion, temperature and rain in a versioned local UserDefaults object, using stable API identifiers. Storage and clock/calendar are injectable. Missing, corrupt or unsupported-version data uses the established Work/Mild/No rain defaults without rewriting the old record until an explicit edit. Unknown enum identifiers fall back independently. No weekday/season/weather inference, forecast service or location permission.

Show a readable summary and disclosure with labelled controls. Preserve saved choices on later local dates and label weather as last-used; explicit confirmation can mark the same choices reviewed today without a request. Date messaging uses the current local calendar/time zone, including while the app remains open over midnight. It is a reminder, not a claim about observed weather.

Changing context restores any pre-request board, cancels generation and invalidates pending alternatives, clears stale alternatives and marks the existing outfit as using earlier settings. Changing and changing back still invalidates the old request. Requests capture immutable context before dispatch; a late success or failure cannot apply after an edit. Retry/generate/swap remains explicit. Swap continues using the current manually selected context (the prior request contract); it does not rewrite the generated outfit's provenance. Offline cache display must not clear the context-dirty reminder.

## Photos and device gate

Garment-only background removal remains device-gated (#125, remaining mask portion of #9). Profile and wearing photos keep crop only. Candidate storage remains orientation-normalized source at the existing 1600 px bound, mask-before-crop, fixed solid `#F2F2F2` compositing and JPEG display. No transparent-export claim, `processedURI` repurposing, cloud fallback, manual brush or automatic garment recognition. Re-edit starts from retained source; any effect integration needs explicit preview/Save/Cancel/restore and existing staged replacement safety.

The current cloud task cannot establish supported-device quality, memory or cancellation responsiveness. A standalone probe may support that investigation; no background-removal production path is enabled without a passed synthetic physical-device gate. API documentation verification and device evidence remain required. A failed/pending gate does not expand the sprint.

## Accessibility and delivery gates

Provide gesture-free crop positioning, labelled actions, scroll/reflow at accessibility sizes, non-color selection state and usable targets. Audit concrete defects, preserving a separate accessible element for each board action. Respect Reduce Motion for affected transitions. Manual VoiceOver, focus and largest-text device checks remain separate from semantic tests.

No SwiftData schema migration is required for preferences. New code must retain all existing photo bytes when untouched and pass an exact-candidate populated in-place upgrade check. iOS build/unit/UI results require macOS; Linux results cannot replace them. Existing model/provider paths are preserved, and no paid evaluation, deployment, upload, new access or spending change is authorized. Release approval must name the concrete artifact.
