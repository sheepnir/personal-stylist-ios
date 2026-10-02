# Bounded Jev selection — implementation verification

## Scope

Generate and swap offer opaque tokens for complete, deterministic-validated wardrobe candidates to the pinned Jev typed Decisions API. The response chooses an existing candidate; it cannot supply assignments or free-form explanations. Required-slot gaps remain on the deterministic path. Candidate payloads contain allowlisted slot, color-family, formality, warmth, and context values only. Names, garment identifiers, notes, profile fields, images, and usage history are not serialized to the provider.

User consent is off by default and tied to the shared policy version. The backend requires that version, explicit provider eligibility, allowlisted model, verified current price, explicit caps, and acknowledged device plus application reservations. The durable application switch starts off. The cumulative evaluation reservation limit never resets or refunds; this intentionally stops conservatively before a total evaluation authorization can be exceeded.

Provider errors and uncertain costs retain bounded reservations. The compact storage codec now preserves generation lookup/backoff/aging fields. Alarms claim no more than 20 lookups per batch before network I/O; skipped reservations do not advance backoff. Costs are reconciled even when the typed output is invalid. Untrusted provider bodies and raw errors are not logged.

Swap selection metadata is separate from the original outfit's provenance. Local swaps clear the prior latest-swap metadata. Undo restores assignments, metadata, and the previous explanation together.

## Reviewed reuse

- #92: only generation response decoding, persistence envelope, DTO/mapping support and corresponding tests are necessary for durable honest attribution. No model selector or additional profile-aware recommendation scope is added.
- #95: fallback-copy mapping, inline board notice, lifecycle tests and copy verifier were adapted to the current board. Spending copy makes no automatic-reset promise.
- #79: its stub approach is insufficient as atomicity evidence. New tests exercise the actual Durable Object under workerd instead.
- #65: no aggregate workflow change is necessary for this bounded implementation. Existing relevant jobs must pass; runtime tests were added to backend CI.

## Local results

- Worker typecheck and **450 unit tests** passed.
- Independent QA: **14 workerd runtime tests** passed, including concurrent overspend prevention, idempotence, actual process restart persistence, UTC rollover, unknown aging, runtime switch and cumulative evaluation limit, plus 27 unknown reservations split into 20 and 7 real alarm lookups.
- **28 synthetic candidate cases** passed, including explicit missing-footwear exclusion; **53 focused candidate/paid-path tests** passed in independent QA.
- Engine **260 tests** and all deterministic evaluation scenarios with two repeats passed. The candidate checks compare validity and membership with deterministic behavior; they do not measure styling preference improvement.
- iOS integrated consent/provenance/fallback suite: **384 tests, one existing skip**, passed before final review fixes. The **20 fallback/lifecycle tests** passed after the fixes. The combined profile-plus-provider candidate then passed **390 tests, one existing skip, zero failures**.
- Contract examples, OpenAPI lint, policy/configuration parity, copy checks and repository checks passed. OpenAPI lint retains two existing warnings.

Separate read-only code review found and rechecked fixes for bounded ledger calls, soft-threshold reporting, alarm batch limits, incomplete candidates, stale swap provenance and Undo explanations. No remaining blocker was found in those fixes. Independent QA authored and ran the runtime batch test. These passes inspected the working snapshot; committed revision review and required CI are still pending.

## Remaining acceptance

No real provider decision, activation, TestFlight upload, physical-device acceptance, or styling quality improvement is claimed. Picker interaction and exact installed upgrade results are separate gates. Paid calls remain off in committed configuration.
