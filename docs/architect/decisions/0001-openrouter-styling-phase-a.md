# 0001: OpenRouter styling, phase A: provider-backed outfit generation behind a mock (issue #26)

| | |
|---|---|
| Owner | Software Architect (ShpDev - Architect) |
| Status | **Accepted** by the CTO, 2026-09-26. Product constraints come from the PM, and the founder approvals below were relayed by the PM/SM. |
| Date | 2026-09-26 |
| Decided by | CTO (technical; see "Decision notes"), 2026-09-26. PM (product items, section 1, including the policy-version decision in section 5.7), 2026-09-26. Founder items: the live model was chosen on 2026-09-26 (section 7.1); spend remains open (section 13). |
| Supersedes | None. Re-records two internal decisions for the public repo (see "Relationship to earlier decisions") |
| Issue | sheepnir/personal-stylist-ios#26, phase A children (A-1 to A-4, iOS-A1 to A3) |
| Path | `docs/architect/decisions/0001-openrouter-styling-phase-a.md` in personal-stylist-ios. Public decisions use `NNNN-<slug>.md` in this folder from now on, replacing the D-nn numbering for new public decisions (CTO, 2026-09-26). |

> **Append-only.** From the commit that adds this file, the text above the "Amendment log" is frozen. A change goes in a dated amendment at the bottom, or in a new ADR that supersedes this one. This record is written for a public repository: it contains no secrets, keys, account identifiers, production cap values, device identifiers, or private operational details.

---

## 1. Context

Verified facts. The code was read at `main` = `df8860d`.

- Outfit generation is deterministic only. `backend/workers/src/routes.ts` `handleGenerate` calls `generateLocal` ("M0-09: Always deterministic — no model call"). Every response carries `generation.fallbackLevel: "DETERMINISTIC"`, `promptVersion: "none"`, `modelId: "deterministic-v0"` (`backend/outfit-engine/src/stage3/config.ts`, `runBuilder.ts`).
- `backend/workers/src/openrouter.ts` `callOpenRouter` forces `provider.data_collection: "deny"`. It has **no callers**, **no timeout** (a plain `fetch`, with no `AbortSignal`), and it puts the upstream error body into the thrown `Error` message.
- The spend ledger (`backend/workers/src/usage.ts`) is a Workers KV read-modify-write keyed by token hash and UTC day. It has no reservation (`reservedUSD` is never written), `recordSpend` has no callers, and KV has no compare-and-swap. The fix is issue #13.
- No allowed-model list, served policy version, or `GET /v1/models` route exists. `docs/openapi.yaml` specifies `/v1/models` as `x-milestone: M2`. The fix is issue #12.
- No feature-flag mechanism exists anywhere in the repo.
- The Stage 4 validator `runStage4` (`backend/outfit-engine/src/stage4/runStage4.ts`) is a pure function that already implements the #26 checklist (see section 6).
- The iOS generate request sets `timeoutInterval = 15` (`App/OutfitEngineClient.swift:512`). Alternatives uses 30 (`:643`).
- Today the iOS generate body sends per garment: `id, displayName, slot, readiness, availability, seasons, colorPrimary{family,hex,name}, pattern, surface, formality, warmth, lastWornOn, daysSinceIntake, setId, keepTogether`. It also sends `sets[]` with `displayName` and `notes`, plus `anchorGarmentId`, `context`, `options`, and `lockedAssignments`. It sends **no `profile`** on generate (the Worker defaults it to `null`). Alternatives sends `profile: {activeRules: []}`.
- The engine package README says: "No network, no OpenRouter, no secrets."

Product and process constraints, as relayed by the PM and SM on 2026-09-26 (not independently verified by the Architect):
- The founder approved **starting #26 phase A with a mocked provider only, zero OpenRouter spend, and the flag off in production, conditional on this ADR.**
- The founder made an **overall application spending cap** a prerequisite for any future paid activation.
- Per the CTO handover (Sprint 6), OpenRouter application spend is zero until the founder authorizes a budget. Local photo upload does not authorize sending photos to a provider.

Product decisions, PM, 2026-09-26 (folded into this record before CTO review):
- **(a)** Profile `summaryText` and context `freeTextNote` are **not sent** to the model. Revisit only together with the consent work (#11) and the deferred AI profile summarization, both of which need founder sign-off (section 4.2).
- **(b)** There is **one canonical policy-version constant**, defined once and shared by the Worker and the app with a repo parity check. A user counts as having accepted only the exact version they were shown. The real policy ID is defined together with the privacy/consent screen that displays it (#11, deferred), and it changes whenever the user-facing privacy text materially changes. Until then the constant is **`null`** ("no policy published"), so nothing counts as accepted and the provider path is off everywhere (section 5.7; final PM decision, 2026-09-26).
- **(c)** Exposing the policy version on `GET /v1/models` alone satisfies #12 AC 2 for Sprint 6, provided it's in `docs/openapi.yaml` and covered by the contract-example check. It isn't added to generate responses (section 10.5 item 5).
- **(d)** `fallbackReason` values `PROVIDER_ERROR`, `INVALID_OUTPUT`, and `SPEND_CAP` are approved, replacing `budget_cap`. "Model not allowed" folds into `PROVIDER_ERROR` for users, but the specific cause stays distinguishable in server logs through an internal cause code that is never sent to clients (section 10.2).
- **(e)** Sending the profile on generate is **out of Sprint 6**. Phase A runs against the mock with **no client profile inputs**. The section 4.1 profile fields are "not before" the FE backlog item for sending the profile, which itself depends on the privacy and consent decisions.

## 2. Phase A constraints (binding for every phase A change)

1. **Mocked provider only.** No code path or test in phase A makes a network request to OpenRouter, in any environment. The provider is an injected interface (`StylistProvider`) with a mock implementation. A test fails if the real client (`callOpenRouter` or `fetch` to the provider host) is invoked while phase A is in force.
2. **Zero OpenRouter spend.** Phase A code does not recognise any "live" flag value (section 9). Adding one is a separate, founder-gated change.
3. **Flag off in production.** The provider path is off unless the flag says otherwise. Production is always off in phase A, enforced in code and not only by configuration. Any environment not positively identified as non-production counts as production (section 9).
4. **No image egress.** No image, thumbnail, or image reference is ever part of a provider payload. The #36 guard stays in front of all content routes.
5. **Safeguards are never trimmed.** If a phase A slice doesn't fit, the slice is cut, not its validation, allowed-model check, budget check, fallback, or flag.
6. **Local-first invariant.** The backend persists no wardrobe, profile, prompt, or model output. Its only state stays the usage ledger (plus the token registry).

## 3. Decision summary

| Topic | Decision |
|---|---|
| Data sent to the model | Structured, enum-valued attributes of **shortlisted candidates only**, with per-request opaque tokens. No names, notes, free text, UUIDs, images, dates, or behavioural signals. Section 4. |
| Privacy | No prompt or output persisted or logged. `data_collection: "deny"` on every call. Upstream error bodies are never logged. Disclosure before any live use. Section 5. |
| Models | Phase A allowlist = the mock model only. Live models are chosen later under the PRD §10.1 procedure and need CTO and founder approval. Allowlist in code, selection in environment config (narrow-only). Intended live model (founder, 2026-09-26): `typesafe/jev-1.13`, a typed-decision model, set at paid activation only (section 7.1). Section 7. |
| Prompt versioning | Immutable prompt modules, with the version recorded in `generation.promptVersion` on every result and a hash guard in CI. Section 8. |
| Validator | Schema and token-map check, then `runStage4` (reused), then contract length and text checks. Any violation means the output is never returned. Section 6. |
| Fallback | Deterministic `generateLocal` on flag-off (silent), provider error or timeout, invalid output, or spend cap. The new `fallbackReason` field is present only when an eligible provider attempt fell back. Section 10. |
| Provider timeout | **8 s** hard `AbortSignal` timeout per attempt, with no repair retry and no secondary model in phase A. Section 10.3. |
| Flag | Worker environment variable `PROVIDER_GENERATION`, parsed fail-closed and off by default. Eligible only when `ENVIRONMENT` exactly matches a non-production allowlist (`staging`), so unset or unknown means production, which means off. Plus an optional per-environment device allowlist and config guards. Section 9. |
| Policy version | One canonical constant in `shared/privacy-policy-version.json`, currently **`null`** (no policy published). The Worker imports it as `CURRENT_PRIVACY_POLICY_VERSION`; the app mirrors it as `nil`; `/v1/models` serves `policyVersion: null`; a repo check enforces parity. Accepted only if the served version is a non-empty string and the stored version equals it exactly, so today nothing is accepted and the provider path is off. Sections 5.6 and 5.7. |
| Paid activation preconditions | An overall application spending cap enforced in the Worker, plus a provider-side key limit, plus the other items in section 11. **Not built in phase A.** |

## 4. Minimum metadata sent to the model (data minimisation)

The Worker builds the provider payload **after** Stage 1 and Stage 2 have run. The model sees only the shortlist (openapi design rule 2, D-03). Garment UUIDs are replaced with per-request random tokens (`g_` + 4 base-36 characters, not derived from the UUID). Sets get `s_` tokens. The Worker keeps the token→UUID map in memory for the request only.

### 4.1 Allowed fields (exhaustive; anything else is excluded)

**Candidate and anchor garments** (shortlisted only):
| Field | Source | Why |
|---|---|---|
| `token` | per-request `g_xxxx` | reference without identity |
| `slot` | `Slot` enum | composition |
| `category` | taxonomy string (PRD App. C), must match the taxonomy list or be dropped | style reasoning |
| `colorPrimary.family`, `colorSecondary.family` | `ColorFamily` enum | harmony works on families (openapi `ColorFamily`) |
| `pattern`, `surface`, `fit` | enums | texture and pattern reasoning |
| `materials[]` | taxonomy strings, max 6; values outside the taxonomy are dropped | fabric reasoning |
| `formality`, `warmth` | 1–5 integers | fit to occasion and weather |
| `seasons[]` | `Season` enum | weather fit |
| `isAnchor`, `isLocked` | booleans | hard constraints |
| `set` | `s_xx` token + `keepTogether` | set atomicity (D-30) |

**Context:** `occasion`, `occasionFormality`, `temperatureBand`, `precipitation`, `timeOfDay`. All are enums, integers, or booleans.

**Profile — NOT BEFORE the FE backlog item "send the profile on generate"** (PM decision (e), 2026-09-26). That item depends on the privacy and consent decisions (#11), and it is out of Sprint 6. In phase A the provider payload's profile block is **empty**, and the mock runs with no client profile inputs. When that item lands, these are the only profile fields allowed: `workEnvironment` (enum), `experimentationLevel` (1–5), request `boldness` (enum), and `activeRules[]` reduced to `{kind, polarity, scope, subject}`. `subject` is limited to `color_family`, `pattern`, `material`, and `category` enum values, or a garment `pair` rewritten to tokens. Pairs that reference garments outside the shortlist are dropped. `buildProviderPayload` still implements the reduction in phase A, so it is tested with a synthetic profile, but no client input feeds it.

**Other:** the `requireSlots` and `accessoryPolicy` options.

### 4.2 Explicitly excluded (never sent to the provider)

- **Images of any kind:** photos, thumbnails, image paths or URLs, base64 (section 2.4).
- **Identity and location:** user name, email, any account or user id, device token, device locator or token hash, request id, and precise location (none is collected, and none may be added).
- **Free text:** garment `displayName`, set `displayName` and `notes`, colour `name`, context `freeTextNote`, profile `summaryText`, `presentationGoals`, `comfortConstraints`, `profession`, and `typicalWeekNotes`. **PM decision (a), 2026-09-26:** `summaryText` and `freeTextNote` are not sent. Revisit only with the consent work (#11) and the deferred AI profile summarization, both needing founder sign-off.
- **Demographics:** `age`.
- **Money and usage:** purchase price or date, cost per wear (openapi rule 4), wear counts, `lastWornOn`, `daysSinceIntake`, `isFavorite`, `wantToWearMore`, `comfortIssue` (scoring signals already applied in Stage 2), `recentOutfits`, and `excludeGarmentSets` (enforced by the Worker, not by the model).
- **Identifiers:** garment and set UUIDs, rule `id`, `provenance`, `supportingSignals`, `capturedAt`, and the colour `hex`.
- **Garments outside the candidate set.**

### 4.3 Names in the rationale without sending names

The model writes garment references in rationale text as placeholders (`{g_4f2a}`). After validation, the Worker renders each placeholder to the garment's `displayName`, which the client already sent to the Worker. So the rationale reads naturally, names never reach the provider, and PRD §9.4 rule 3 (names must match the assigned garments) holds by construction. This takes the "opaque ids and structured attributes only" option from the internal decision D-68 for the **provider** path only. The client→Worker payload is unchanged. *(2026-09-26: the intended live model writes no text, so for it the rationale is composed on the server and no placeholders are used; see section 7.1.4.)*

### 4.4 Enforcement
- A single pure function `buildProviderPayload(request, shortlist)` is the only producer of the payload. It builds from an allowlist and never copies and strips.
- A test asserts that the payload's key set equals the allowlist exactly, and that it contains none of: a UUID pattern, any `displayName`, any image key or value (the #36 matcher), or any excluded key. A second test sends a request stuffed with every excluded field and asserts none reaches the mock.
- Generate doesn't send `profile` today [code], and sending it is out of Sprint 6 (PM decision (e)). The provider payload's profile block is empty in phase A. A test asserts that the phase A payload built from a real generate request has an empty profile block.

## 5. Privacy requirements

1. **Retention (backend).** Nothing from a provider request or response is persisted. Ledger entries hold only: attempt id, task, model id, reserved upper bound, actual cost, outcome state, provider generation id (an opaque id used for reconciliation), and timestamps (D-20 content-free ledger).
2. **Logging redaction.** Never log request bodies, provider payloads, prompts, model outputs, rendered rationales, display names, device tokens, locators, or token hashes. Allowed log fields: `promptVersion`, `modelId`, outcome enum, `fallbackReason`, the internal `fallbackCause` (section 10.2), latency, HTTP status, provider error *code*, and cost. The provider client must throw an error that carries status and code only. The current `callOpenRouter` includes the upstream response body in `Error.message`, and routes log errors with `console.error`, so it must change before any live use. Phase A adds a test that a provider error's message contains no body text.
3. **Provider data-use settings (before any live call; not needed for the phase A mock).** Every request carries `provider.data_collection: "deny"` (already code-enforced, VF-03) and `provider.require_parameters: true` when structured output is requested (VF-05 partial). Account-level training opt-out and prompt-logging settings must be verified by the founder and recorded privately with a date. `dataPolicy.verifiedOn` stays `null` until then. Retention claims to users stay at "training excluded" unless zero-data-retention routing is required and verified (internal D-67 / Q-ON-6).
4. **Consent and disclosure.** Text-only generation needs no image consent (openapi: image-free generate omits `privacyConsent`). Before the flag is turned on in any environment that holds real user data, the app must say in plain language which model is in use and that garment attributes and style preferences are sent to it (PRD §12.3), and the privacy claims must match section 4 (D-68). Phase A (mock, no data leaves the Worker) needs no new disclosure.
5. **Auth scope.** The provider path is available only to per-device tokens. A request authenticated with the legacy shared token (`AuthContext.legacyShared`) always takes the deterministic path, because it has no per-device ledger identity.
6. **Policy version (PM decision (b) and the final PM decision, 2026-09-26).**
   - **Product rules (PM):** the real policy ID is defined together with the privacy/consent screen that displays it (#11, deferred). The ID changes whenever the user-facing privacy text materially changes. A user counts as having accepted **only the exact version they were shown**.
   - **One canonical constant, defined once:** `shared/privacy-policy-version.json` at the repo root, containing `{"policyVersion": null}` today. Nothing else defines the value. #11 later replaces `null` with the real ID, in the same change as the screen that displays it.
   - **Worker:** `backend/workers/src/policy.ts` imports the JSON (`tsconfig` already has `resolveJsonModule: true`, and wrangler bundles it) and exports `CURRENT_PRIVACY_POLICY_VERSION: string | null`, which is `null` today. `GET /v1/models` serves it as `policyVersion` (#12), so `policyVersion: null` means "no policy published". There is no environment override.
   - **App:** one Swift constant, `static let currentPrivacyPolicyVersion: String? = nil`, in `App/PrivacyPolicyVersion.swift`. The app can't read a repo file at compile time without adding a bundle resource, so the value is mirrored. #11 writes the shown version into `PrivacyConsentEntity.policyVersion` when the user accepts.
   - **Why `null`, not a sentinel string (PM decision):** a magic string could accidentally get stored as an "accepted" version. `null` can't match anything.
   - **Acceptance rule:** accepted **if and only if** the served version is a **non-empty string** **and** the stored accepted version equals it exactly (case-sensitive, no trimming). So `null` never matches anything, including an empty or missing stored value. Today every device counts as not accepted, and the provider path is **off everywhere**, mock included (fail-closed). A not-accepted request takes today's deterministic path with no `fallbackReason` (consent not given is the product working as configured, like flag-off). The app applies the same rule to decide whether to prompt (#11). The Worker enforces it independently, because a client-side check isn't a control.
   - **Parity (repo check):** a new `scripts/check-policy-version-parity.py`, run in `repo-checks.yml` next to the image-guard parity step. It fails unless (1) the JSON value is `null` and the Swift constant is `nil`, or both are the same non-empty string later; (2) the Worker's `policy.ts` takes the value from the JSON import rather than a literal; (3) every served or accepted `policyVersion` in the golden examples of `scripts/verify-openapi-contract-examples.py` is `null` today (that script should read the JSON file directly); and (4) no `onboarding-privacy-*` literal appears anywhere in the repo.
   - **Engineering cleanup, in the #12 PR, so nothing implies a real policy:** the migration fixture `Persistence/SwiftData/LegacyStoreFixtures.swift:204` changes from `"onboarding-privacy-v1"` to the obviously fake `"test-fixture-policy"`. The contract goldens `scripts/verify-openapi-contract-examples.py:43,56` change from `"onboarding-privacy-v0"` to `null`, which needs the `PrivacyConsent.policyVersion` schema change in section 10.5 item 5.
   - **Carrier (open, section 13 item 2):** openapi says image-free generate must omit `privacyConsent`, so the Worker has no way to see the stored accepted version today. Recommendation: an optional `GenerateRequest.acceptedPolicyVersion` (string, `maxLength: 64`, no image token, so it isn't affected by #36). The app sends it only when it holds a stored acceptance. While the served version is `null`, the carrier makes no difference, because nothing can be accepted. A-3 tests inject a test served value and the carrier.

### 5.7 Policy-version value: **`null` until #11** (final PM decision, 2026-09-26)
- **#12 is not blocked.** It delivers the mechanism now: the canonical constant (`null`), the Swift mirror (`nil`), `policyVersion: null` on `/v1/models`, the parity check, the fixture and golden cleanup, and contract-example coverage.
- **Evidence behind the decision [code, `df8860d`]:** the app displays no onboarding privacy text (`Features/Profile/ProfileDraftView.swift:4`: "Welcome + privacy remain HELD this wave"; no view renders privacy or consent copy). `"onboarding-privacy-v1"` existed only in a migration-test fixture (`LegacyStoreFixtures.swift:204`), and `"onboarding-privacy-v0"` only in synthetic contract goldens (`verify-openapi-contract-examples.py:43,56`). `PrivacyConsentEntity` (`DomainModels.swift:713`) is never instantiated, and the live camera path writes `policyVersionAtChoice = ""` (`SwiftDataPersistenceStore+Camera.swift:22-27`; default at `DomainModels.swift:759`). No real policy has been shown or accepted, so none is published.
- **What changes it:** #11 (deferred) defines the real ID together with the screen that displays it, sets it in the JSON and the Swift constant in one PR, and the parity check enforces equality from then on.

## 6. Validator for provider output (#26 A-2)

Provider output is untrusted. It is validated in this order, and the first failure aborts.

1. **Parse and schema.** *(For a typed-decision model, including the intended live model and the phase A mock, step 1 is section 7.1.3 instead.)* Output must parse as JSON and match the model output schema exactly: `assignments[]` of `{slot: Slot, garment: token|null, gapReason?: string ≤120}` and `rationale {summary, pairingNotes ≤3, teachingNote|null, cautions ≤2}`. Additional properties are rejected. When the provider supports enum-constrained output, each slot's `garment` enum is the tokens for that slot (PRD §9.4).
2. **Token map.** Every token must be in the request's map. An unknown token is a `CANDIDATE_SET_MEMBERSHIP` violation. Map tokens back to UUIDs.
3. **`runStage4`, reused unchanged**, with the same Stage 2 `candidateIds` and `fixed` that built the prompt, plus the request wardrobe, context, profile, sets, and options, and `fallbackLevel: "NONE"`. Any violation fails the output: candidate membership, anchor missing or mismatch, slot uniqueness, accessory limit, accessory category distinctness, duplicate garment, required slot without garment or gap, combination rules, set integrity, lock missing or mismatch, accessory policy.
4. **Checks `runStage4` does not do (added for the provider path):**
   - The outfit must differ from every `options.excludeGarmentSets` entry in at least one non-locked slot. Otherwise it's invalid (the deterministic path handles `noAlternativeReason`).
   - Rationale placeholders may reference only assigned tokens. Text may contain no URLs, email addresses, phone-number patterns, raw UUIDs, or unrendered braces.
   - After placeholder rendering, the openapi `Rationale` limits are **hard** limits: summary ≤200, pairing notes ≤140 each, teaching note ≤160, cautions ≤120 each. (`runStage4` only raises a caution above 400 characters for the summary and doesn't check the others.)
   - `gapReason` only on rows with no garment.
5. **Cautions** from `runStage4` (layer requirement, rationale quality, locked disliked pair) are merged into `rationale.cautions` as `generateLocal` does today, max 2.

**On any failure:** the output is discarded and never sent to the client. The ledger attempt is reconciled at the mock or actual cost (a failed output still costs money when live). The response falls back per section 10 with `fallbackReason: "INVALID_OUTPUT"`. Violation codes are logged (codes only, no content). There is **no repair retry in phase A** (see section 10.3).

## 7. Allowed models

- **Sources name no production model.** PRD §10.1 pins none and prescribes a procedure: three candidates across the cost range, checked against the live catalogue (vision, structured output, ≥32k context), with slugs and check date recorded. One candidate is recorded internally; none is approved. The first-comparison budget is internal D-09, Proposed, not authorized.
- **Phase A allowlist: exactly one entry, the mock model id `mock/stylist-v0`.** It is not a real provider slug, so a misconfiguration can't reach a paid model.
- **Mechanism:** the allowlist is a reviewed code constant (`backend/workers/src/models.ts`). Each entry has slug, role eligibility (primary or secondary), per-million input and output prices plus the check date (needed for the D-34 upper-bound reservation), and capability flags. Environment variables `STYLIST_PRIMARY_MODEL` and `STYLIST_SECONDARY_MODEL` pick from the allowlist per environment. They can **only narrow**: a value not in the allowlist counts as unconfigured, which means no provider call. Widening the list is a code change with review. `GET /v1/models` (#12) reports the configured models.
- **Live models: Proposed, needing CTO and founder decisions.** Candidates are selected under PRD §10.1 at the time the founder authorizes a budget, and they're added by a PR that records slug, prices, and check date. **Spend implications:** every allowlisted model's price feeds the upper-bound reservation. A frontier model raises the per-attempt reservation and so reaches the per-device and global caps sooner. The soft threshold (D-20) is informational only: it is surfaced in the usage summary and telemetry and does not switch models; only the hard cap triggers the deterministic fallback (CTO, 2026-09-26).

### 7.1 Intended live model: `typesafe/jev-1.13` (founder decision, relayed by the CTO, 2026-09-26)

**Status.** The founder chose the model. Nothing about the Sprint 6 posture changes: the phase A allowlist stays `mock/stylist-v0` only, `PROVIDER_GENERATION=mock` is eligible only when `ENVIRONMENT` is exactly `staging`, there is no OpenRouter spend, the flag is off in production, and `dataPolicy.verifiedOn` stays `null`. The budget is still open (section 13).

**Config value (intended, not set anywhere in Sprint 6).** At paid activation the live Worker configuration sets `STYLIST_PRIMARY_MODEL = "typesafe/jev-1.13"`, which selects from the section 7 allowlist. The activation PR adds the matching allowlist entry to `backend/workers/src/models.ts` (#12's mechanism), with its prices and check date recorded in code and nowhere in this record. Call sites read the configured model and never hard-code a slug. The slug is pinned, and the floating "latest" alias is not used, because thresholds and evaluations are tied to one version. No secondary model is named; the soft threshold is informational only (CTO, 2026-09-26).

**Rejected: `typesafe/jev-router`.** OpenRouter's public listing publishes no usable price for it: the models API returns a sentinel instead of a per-token price, the model has no listed endpoints, and it routes each request to other models. An unpublished or variable price can't produce the upper-bound reservation (section 12) or pass the section 11 price check, so it's incompatible with a hard cap.

**Publicly verified facts (OpenRouter listing and docs, checked 2026-09-26; prices recorded internally only).** Text input only. Output modality `decisions`. Context 32,000 tokens. Max completion tokens 28,800. `supported_parameters` is empty (so no `response_format`, `temperature`, `max_tokens`, or `tools`). The endpoint metadata sets `supports_tool_choice` to true for all four values, **but** the model page and the Jev docs say the model runs on OpenRouter's Decisions API (`POST /api/alpha/decisions`, or the same-schema `POST /api/v1/systemone`) "rather than the OpenAI-compatible chat endpoint", and that it "does not produce reasoning traces, explanations, or free-form text". Tool or function calling on chat completions is therefore **not** a documented way to call this model. This record designs for the documented Decisions API.

#### 7.1.1 What the model can return
A Decisions request carries `state` (text or JSON) and named `questions`, each of which is `choice` (one option key from a map the caller defines, up to 255 options per question), `noul` (probability of yes), or `score` (a position on an ordered scale). The answer to a choice is `{type, choice, confidence, probabilities}`, and `choice` is always one of the caller's option keys. All questions in a request are answered independently and in parallel, and they can't see each other's answers. **The model can select wardrobe items (as option keys). It can't write rationale text.** So the conservative case applies: rationale is composed on the server.

#### 7.1.2 Request shape (built by `buildProviderPayload`; section 4 allowlist unchanged)
- One `choice` question per slot to fill, with id `slot_<SLOT>`. Its option keys are that slot's shortlist tokens (`g_xxxx`), in Stage 2 rank order. Each option's description is that garment's section 4.1 allowlisted attributes (an object), so the model doesn't need to look anything up elsewhere in `state`. An optional slot also gets the option `none`. Locked and anchor slots are never asked.
- A `keepTogether` set is offered as a single `s_xx` option in its first slot's question, and the partner slot's answer is ignored when the set is chosen (the documented "speculative fan-out" pattern).
- Accessories, only when `accessoryPolicy` allows: one `noul` per accessory candidate. Code picks at most three, with distinct categories.
- `state` holds only the section 4.1 context, the anchor and locked garments' allowlisted attributes, and the options. The instruction and criteria wording is fixed, versioned prompt text (section 8).
- The section 4.4 key-set test covers the **whole** request body, `state` plus `questions`.

#### 7.1.3 Model output schema: replaces section 6 step 1 for this output shape (A-2)
The provider output is **no longer** JSON text of the form `assignments[] + rationale{}`. It is a Decisions response. Step 1 becomes:
1. The body parses, and has `answers` (object), `model` (string), and `usage.input_tokens` and `usage.output_tokens` (integers). Otherwise `OUTPUT_PARSE`.
2. `model` equals the configured slug, or that slug plus its dated snapshot suffix (a hyphen and eight digits). Otherwise `OUTPUT_MODEL_MISMATCH`, a new server-only cause under `INVALID_OUTPUT`.
3. The set of answer ids equals the set of question ids exactly. Every answer's `type` matches its question. `choice` is a string that is one of **that question's** option keys. `noul` is a number from 0 to 1. Otherwise `OUTPUT_SCHEMA`. A missing answer is the typed equivalent of a "missing tool call".
4. Map the answers to `assignments[]`: a token becomes `garment`, `none` becomes a gap on an optional slot, and `s_xx` expands to both set members. Then continue with section 6 steps 2 to 5 **unchanged** (token map, `runStage4`, the `excludeGarmentSets` check, and cautions). An item id that isn't in the request's token map is still `CANDIDATE_SET_MEMBERSHIP`.
5. The section 6 step 4 checks on **model-written** text (placeholders, URLs, UUIDs, braces) don't apply to this shape, because the model writes no text. The hard length limits still apply to the composed rationale.
Any failure: `fallbackReason: "INVALID_OUTPUT"`, exactly as in section 10.1.

#### 7.1.4 Rationale: server-side template (section 4.3 placeholders don't apply to this model)
After validation, the Worker composes the rationale with the engine's existing `templateRationale`, fed by the validated assignments. Pairing notes and cautions come from the chosen garments' attributes and the context, `teachingNote` is `null`, and `gapReason` comes from the existing `gapReasonFor`. There is one fixed provider-path `summary` string that must not claim the model wrote the explanation. Names are rendered from the client's `displayName` on the Worker, so none reaches the provider. **Client contract: no change.** `Rationale` already requires only `summary`, the other fields are already optional, the limits stay the same, `OutfitAssignment.gapReason` is unchanged, and no field gains a source or enum. iOS decoding and rendering are unaffected. Reason-code questions mapped to fixed copy aren't used, because in a single request they'd be answered without seeing the items chosen. A two-step "explain the chosen outfit" call is a later option that needs a timeout re-budget (section 10.3).

#### 7.1.5 Mock provider (phase A)
`mock/stylist-v0` takes the same Decisions request object and returns the same Decisions response shape, with no network. By default, for each choice it picks the first listed option (the top Stage 2 rank), and it answers `0.5` for every noul. It has fault modes for tests and evals: malformed JSON, a missing answer, an extra answer, a wrong `type`, a choice not offered, a model mismatch, a valid-shape combination that fails `runStage4` (for example a split set), an HTTP error, and a timeout. Sprint 6 tests therefore run the real build → validate → map → `runStage4` → template path.

**Mocked example, not a real provider response.** The mock's output for a two-slot request, in the documented Decisions response shape (a live response differs only in `id`, `model`, `provider`, and an added `usage.cost`):
```json
{
  "id": "mock-dec-0001",
  "model": "mock/stylist-v0",
  "provider": "mock",
  "answers": {
    "slot_TOP": { "type": "choice", "choice": "g_4f2a", "confidence": 0.8, "probabilities": { "g_4f2a": 0.9, "g_9k1c": 0.1 } },
    "slot_OUTERWEAR": { "type": "choice", "choice": "none", "confidence": 0.7, "probabilities": { "none": 0.85, "g_2m7p": 0.15 } }
  },
  "usage": { "input_tokens": 912, "output_tokens": 40 }
}
```
**Mocked example: the mapped client response fragment** (the anchor BOTTOM is fixed; UUIDs and names are illustrative):
```json
{
  "assignments": [
    { "slot": "BOTTOM", "garmentId": "7d1e2c90-0000-4000-8000-000000000001", "isAnchor": true },
    { "slot": "TOP", "garmentId": "7d1e2c90-0000-4000-8000-000000000002" }
  ],
  "rationale": { "summary": "<fixed provider-path summary copy>", "pairingNotes": ["Anchored on Grey chinos.", "Paired top Navy knit (NAVY)."], "teachingNote": null },
  "generation": { "modelId": "mock/stylist-v0", "promptVersion": "outfit-t2-d1", "latencyMs": 12, "fallbackLevel": "NONE", "costUSD": null }
}
```
Because OUTERWEAR is optional, choosing `none` leaves it out of the outfit, with no row, as `generateLocal` does today. A required slot has no `none` option, and if it has no candidates it gets a gap row whose `gapReason` comes from `gapReasonFor`.

#### 7.1.6 Paid-activation items (a later issue, not Sprint 6)
The real Decisions API client (the existing `callOpenRouter` posts to chat completions and can't be used), with the 8 s timeout, error redaction, `provider.data_collection: "deny"`, `provider.allow_fallbacks: false`, and `provider.max_price` set from the allowlisted prices. **Section 11 price check:** a price is valid if it is a finite number ≥ 0. A listed price of zero is valid. A missing value, null, a non-numeric value, or a negative value (including the listing's sentinel for unpublished prices) means unpriced, which gives `PROVIDER_ERROR` with no ledger call. **Cost bound:** no `max_tokens` parameter exists, so the output term uses the listed completion price (possibly zero) times the listed max completion tokens, and the input term uses the 32,000-token context length times the prompt price. The Worker refuses to send, with `PROVIDER_ERROR`, if the serialized request exceeds a byte budget sized under the context length. Reconciliation uses `usage.cost` or the generation record (section 12). Other items: a confidence threshold (tuned on evals) below which the output counts as `INVALID_OUTPUT`; Designer copy for the provider-path summary; `/v1/models` descriptor values (`supportsVision: false`, `supportsStructuredOutput: false`, `contextWindow: 32000`); re-checking the listing on the activation date. The activation price check has to read the per-model endpoints resource or the models list filtered by `output_modalities=decisions`, because the default models list omits decision models. Deviations from PRD §10.1 are recorded there as well: one founder-chosen model, not three candidates; no vision, which is not needed, since no images are sent; no `response_format`, since typed decisions replace it; and a context length of exactly 32,000.

## 8. Prompt versioning (#26 A-1)

- Each prompt is an immutable module in the engine package (pure, no network): `backend/outfit-engine/src/provider/prompts/outfit-t2-v1.ts`. It exports `{ version: "outfit-t2-v1", system, render(payload), outputSchema }`. The output schema is part of the version. *(2026-09-26: for a typed-decision model the module exports the fixed instruction and criteria text, `buildRequest(payload)`, and the expected answer types instead of `system`, for example `outfit-t2-d1`. The registry, hash test, and `promptVersion` recording are unchanged.)*
- A registry test hashes (SHA-256) the system text plus the serialized output schema and compares it to the hash registered for that version. Editing a prompt without adding a new version fails CI. Old versions are never edited or deleted while stored outfits reference them.
- Every generate response records the version in `generation.promptVersion` (existing required field). The deterministic path keeps `"none"`. The Worker also sets `generation.modelId` (existing) and `candidateSetHash` (existing). `GET /v1/models` reports the current `promptVersion` (the `ModelConfigResponse` field already exists).
- Eval runs record `promptVersion` per arm. The client stores it with the outfit (iOS-A1).

## 9. Feature flag

**Mechanism (the simplest adequate one for a Cloudflare Worker with per-environment `wrangler` config):**
- A Worker plain-text environment variable **`PROVIDER_GENERATION`**, read per request from `env`.
- **Parsing is fail-closed:** only the exact lowercase string `mock` enables the provider path. Missing, empty, whitespace, different case, `true`, `1`, `on`, `live`, or any other value means **off**. An unrecognised non-empty value logs one warning per isolate (the value, never a secret).
- **Production is forced off: environment allowlist, not a production check** (amended 2026-09-26, security fix found by the CE). The live production Worker deploys from the **top-level** configuration (`--env=""`), where `ENVIRONMENT` is unset, so an `ENVIRONMENT === "production"` check would never fire. Rule:
  - The provider path is eligible only if `ENVIRONMENT` **exactly** matches the non-production allowlist `NON_PRODUCTION_ENVIRONMENTS = ["staging"]` (a code constant in `src/flags.ts`). `staging` is the only non-production value in the repo today [code: `wrangler.toml` `[env.staging] vars`, generated `worker-configuration.d.ts` `"production" | "staging"`]. Adding another value, for example `development` for local `wrangler dev`, is a reviewed code change.
  - Missing, empty, `production`, any other value, or a different case means **production**, which forces the flag off. `PROVIDER_GENERATION = "mock"` on its own is never enough.
  - **This is the first read of `ENVIRONMENT` in `backend/workers`.** Today `src/types.ts:29` only declares it, and nothing reads it (BE-confirmed; matches a code search at `df8860d`).
  - We do **not** add `ENVIRONMENT = "production"` to the live configuration. The rule is safe without it.
  - The live production configuration sets `PROVIDER_GENERATION = "off"` explicitly at the top level **and** in every `[env.*]` block. This is recorded in the private ops repo only.
- **Config guards:**
  - `scripts/check-provider-flag-off.py` (Python 3.11+ standard-library `tomllib`, no new dependency), run in Repo Checks. It fails if the committed sample `backend/workers/wrangler.toml` sets `PROVIDER_GENERATION` to anything but `"off"` at the top level or in `[env.production]`. The sample adds explicit `"off"` in both places in the A-3 PR.
  - The same script runs as a CE pre-deploy step against the private live configuration, in a strict mode that also requires an explicit `"off"` at the top level and in every `[env.*]` block.
  - After deploy, the CE confirms the deployed version's variables with `wrangler versions view <version-id> --json` and records it in the deploy packet.
  - **No `providerEnabled` (or similar) field on the unauthenticated `/health`.** Flag state isn't exposed publicly.
- **Optional device allowlist:** `PROVIDER_GENERATION_DEVICES` is a comma-separated list of device locators (the random, non-secret UUID prefix of a per-device token). When it is set, only those devices are eligible. When unset, every per-device token in that environment is eligible. Values live only in per-environment config, never in the repo.
- **Eligibility, all required:** flag resolves to `mock`, `ENVIRONMENT` is on the non-production allowlist, the token is per-device (not legacy), the device is on the allowlist when one is set, the request's accepted policy version equals the served version (section 5.6 rule), and a primary model is configured and allowlisted. If the flag is off, the policy version isn't accepted, or the device isn't eligible, the request takes today's exact deterministic path: no ledger access, no provider call, no `fallbackReason`.
- **Tests (required in A-3):** a table test of the parser (each off value above), and an environment table: `ENVIRONMENT` unset + `mock` → off; `production` + `mock` → off; unknown value (for example `prod`, `Staging`, `""`) + `mock` → off; `staging` + `mock` → on. Also tests for `check-provider-flag-off.py` (off accepted; `mock`, missing-in-strict-mode, and other values rejected); flag off means a spy provider is never called and `USAGE_LEDGER` or the ledger object is never touched (mirrors the existing test "does not touch USAGE_LEDGER on the deterministic path", `tests/basic.test.ts`); flag off means the response has no `fallbackReason` and matches today's shape; device allowlist on and off; legacy token denied; policy version: served `null` + any stored value (including empty) → no provider call; served test string + missing, empty, different, or different-case stored value → no provider call and no `fallbackReason`; served test string + an exact match → eligible.
- **Turning it on later:** (a) non-production for the mock: set the variable in that environment's local config and deploy the config. (b) any live value requires a new code change adding `live`, gated on section 11, then a release decision (a production flag change counts as a release per DevFlow draft SOP-010).
- **Deviations from DevFlow draft SOP-004 item 18: ACCEPTED by the CTO for phase A (2026-09-26).** Item 18 asks that a flag change need no deployment and that production flag settings be a CODEOWNERS path. Here, a Worker variable change deploys a new Worker version (configuration only, no code), and production values live in the gitignored local config, recorded in the private ops repo rather than under CODEOWNERS. **Revisit before any live production enablement** (for example, flag values in a Durable Object or KV). This mechanism stays in this record; there is no separate flag ADR.

## 10. Deterministic fallback and the `fallbackReason` contract

### 10.1 Behaviour
| Situation | Provider call? | Response |
|---|---|---|
| Flag off, device ineligible, legacy token, or policy version not accepted | No | Today's deterministic response. **No `fallbackReason`.** |
| Stage 1 problem (lock or set conflict, not ready, below minimum) | No | Same 400 or 422 problem as today (openapi rule 8: rejected before any model call) |
| Eligible, but primary model not configured or not allowlisted | No | Deterministic, `fallbackReason: "PROVIDER_ERROR"` |
| Eligible, and the ledger refuses the upper-bound reservation (per-device cap, and later the global cap), **or a ledger can't be read or updated** | No | Deterministic, `fallbackReason: "SPEND_CAP"`; `spendState: "HARD_CAP_DETERMINISTIC"` when a cap was reached |
| Provider error, network failure, rate limit, or **timeout** | Yes | Deterministic, `fallbackReason: "PROVIDER_ERROR"`. A timeout leaves the reservation in the unknown state (section 12) |
| Output fails the section 6 validator | Yes | Deterministic, `fallbackReason: "INVALID_OUTPUT"` |
| Valid output | Yes | `fallbackLevel: "NONE"`, `modelId` = the provider model, `promptVersion` = the prompt version, no `fallbackReason` |

The fallback always runs `generateLocal` on the same request, so the result is identical to today's deterministic result. The status stays 200 (generate never returns 429 or a 503 for provider problems, per openapi). If `generateLocal` itself returns a problem, that problem is returned as today.

### 10.2 `fallbackReason`: decision
- **Name:** `fallbackReason`, in `GenerationMeta` next to `fallbackLevel`.
- **Values (minimal set, UPPER_SNAKE_CASE like `FallbackLevel`, `spendState`, and Problem `code`):**
  - `PROVIDER_ERROR`: the provider path was eligible but couldn't produce a response. This covers error, network failure, rate limit, **timeout**, and a configured model that isn't allowed or configured. Separate `TIMEOUT` and `MODEL_NOT_ALLOWED` values were rejected: the user-facing meaning ("the stylist model was unavailable") and the client behaviour are the same, and the distinction belongs in server logs. Model-not-allowed is a configuration defect, not a user state.
  - `INVALID_OUTPUT`: the provider responded, but the output failed validation.
  - `SPEND_CAP`: the spend safeguard refused the attempt (per-device, later global). Named to match the contract's existing "spend cap" vocabulary (`SPEND_CAP_REACHED`, `spendState`), instead of the proposed `budget_cap`.
  - **No `FLAG_OFF` value:** flag-off isn't a fallback. It is the product working as configured, so the field is absent.
  - **Approved by the PM on 2026-09-26** (decision (d)), including the rename from `budget_cap`.
- **Internal cause code (server-only, never sent to clients):** every fallback also sets `fallbackCause`, which is written only to Worker logs and diagnostics (the structured log line and the eval harness output). Values:
  - under `PROVIDER_ERROR`: `MODEL_NOT_CONFIGURED`, `MODEL_NOT_ALLOWED`, `PROVIDER_TIMEOUT`, `PROVIDER_RATE_LIMITED`, `PROVIDER_HTTP_ERROR` (with the HTTP status), `PROVIDER_NETWORK`
  - under `INVALID_OUTPUT`: `OUTPUT_PARSE`, `OUTPUT_SCHEMA`, `OUTPUT_TOKEN_MAP`, `OUTPUT_STAGE4` (with violation codes), `OUTPUT_EXCLUDED_SET`, `OUTPUT_TEXT`, `OUTPUT_LENGTH`
  - under `SPEND_CAP`: `DEVICE_CAP`, `DEVICE_LEDGER_UNAVAILABLE`, and with section 11: `GLOBAL_CAP`, `GLOBAL_LEDGER_UNAVAILABLE`
  
  The code is a TypeScript union in the Worker, not an openapi type. Enforcement: `GenerationMeta` keeps `additionalProperties: false`, and an A-3 test asserts the serialized response contains no `fallbackCause` key and none of the cause values. Adding a cause value doesn't change the contract.
- **Optionality and absence:** optional and **not nullable**, so it is omitted rather than sent as `null`. Absent means no eligible provider attempt fell back: either the provider result was used (`fallbackLevel` other than `DETERMINISTIC`) or the provider path wasn't eligible (flag off, ineligible device, legacy token). When present, `fallbackLevel` is `DETERMINISTIC`. Production never sends it while the flag is off.
- **Unknown future values:** clients must decode the field as a string, not a closed enum. They treat any unrecognised value like `PROVIDER_ERROR` (generic "built without the stylist model" notice) and never fail decoding.
- **Client rule:** the fallback notice is keyed on the **presence** of `fallbackReason`, never on `fallbackLevel` alone.

### 10.3 Provider timeout
- **Verified:** the iOS generate `timeoutInterval = 15` s (`App/OutfitEngineClient.swift:512`), and `openrouter.ts` has no timeout (bare `fetch` at lines 55–64).
- **Decision:** one provider attempt with a hard **8 s** `AbortSignal.timeout(8000)`. There is **no repair retry and no secondary-model attempt in phase A**, because either one would push the worst case past the client's 15 s.
- **Budget, 15 s total on the client:** request upload and Worker cold start, Stage 1–2 (the engine latency gate budgets the full deterministic pipeline at p95 ≤ 400 ms for a 100-garment wardrobe and ≤ 900 ms for 200, per `backend/outfit-engine/scripts/latency-gate.ts`), a ledger reservation, the 8 s provider cap, validation (pure, milliseconds), reconciliation, deterministic fallback (same ≤ 900 ms p95), and the response download. That leaves roughly 4–5 s of margin for mobile networks. It also sits inside PRD §9.5's 10 s escalation threshold. (Inference: iOS `timeoutInterval` is an idle-interval timeout, and the Worker sends no bytes until it finishes, so the whole Worker time counts against it.)
- A timeout maps to `fallbackReason: "PROVIDER_ERROR"`, and the ledger attempt stays **unknown** (section 12).
- Repair and secondary-model steps (PRD §9.5 levels 1–2) are deferred until live timing data exists. Re-budget before adding them.

### 10.4 Contract clarification: honest rendering of `DETERMINISTIC` (product decision, PM, 2026-09-26)
`docs/openapi.yaml` `info.description` rule 5 says a 200 with `fallbackLevel: DETERMINISTIC` must be rendered "honestly rather than treating it as a normal result", and the `FallbackLevel` description says "the client must say so". Today every production result is deterministic, because no stylist model is offered, so deterministic output is the product and not a degradation. **Clarification:** clients show the fallback notice only when `generation.fallbackReason` is present. A `DETERMINISTIC` result without `fallbackReason` is rendered as a normal result. The openapi wording changes below make this explicit, so the contract isn't silently violated.

### 10.5 Exact `docs/openapi.yaml` changes (one PR, owned by BE with #26 A-1 or A-3; bump `info.version` 0.3.3 → 0.3.4)

1. `info.description`, rule 5: replace the second and third sentences with:
```yaml
    5. **Failures degrade, they do not error.** The fallback ladder (PRD §9.5) means a
       successful 200 may carry `fallbackLevel: DETERMINISTIC`. When the stylist model was
       eligible for the request but not used, the response also carries
       `generation.fallbackReason`, and the client must then say so rather than presenting
       the result as a stylist-model result. A `DETERMINISTIC` result **without**
       `fallbackReason` means no stylist model was offered for this request (for example,
       provider generation is not enabled in this deployment); clients render it as a normal
       result. Reaching the **hard** daily spend cap is one such trigger: generation, rationale,
       and summary fall back to deterministic output with a 200; only tasks with no fallback
       return 429.
```
2. `components.schemas.FallbackLevel.description`: replace with:
```yaml
      description: |
        Which rung of the failure ladder produced this result (PRD §9.5).
        `DETERMINISTIC` means no stylist model was involved. Whether the client must tell the
        user is decided by `GenerationMeta.fallbackReason`: present means the model was eligible
        but not used (say so); absent means no model was offered (render normally).
```
3. `components.schemas.GenerationMeta.properties`: add (not in `required`):
```yaml
        fallbackReason:
          type: string
          enum: [PROVIDER_ERROR, INVALID_OUTPUT, SPEND_CAP]
          description: |
            Present only when the stylist-model path was eligible for this request and the
            result fell back to the deterministic engine; then `fallbackLevel` is
            `DETERMINISTIC`. Omitted (never null) when the model result was used or when no
            model path was offered (for example, provider generation disabled).
            `PROVIDER_ERROR` — the provider failed, timed out, was rate limited, or the
            configured model is not allowed. `INVALID_OUTPUT` — the provider answered but the
            output failed validation. `SPEND_CAP` — a spend cap refused the paid attempt (see
            `spendState`). Clients MUST treat unrecognised values like `PROVIDER_ERROR` and
            MUST NOT fail decoding on them; new values may be added without a major version.
```
4. `components.schemas.PrivacyConsent.properties.wardrobeImagesAcceptedAt`: add `maxLength: 64` (the #36 decision). The Worker bounds this value at 64 characters with a real date-time parse. The field stays `type: string, format: date-time`.
```yaml
        wardrobeImagesAcceptedAt:
          type: string
          format: date-time
          maxLength: 64
          description: When the user accepted wardrobe-image processing under `policyVersion`.
```
5. Owned by **#12**, in its own openapi PR (listed here for completeness, not required for A-1 or A-3). Remove `x-milestone: M2` from `/v1/models`, and add to `ModelConfigResponse` (in `required`):
```yaml
        policyVersion:
          type: [string, 'null']
          minLength: 1
          maxLength: 64
          description: |
            The privacy / data-use policy version this deployment serves. `null` means no policy
            is published, and then no stored acceptance counts. A client's stored accepted
            `PrivacyConsent.policyVersion` counts as accepted only if this value is a non-empty
            string and the stored value equals it exactly; otherwise the user must accept the
            shown version before any stylist-model path is used.
```
   The file is OpenAPI **3.1.0**, so nullability is written as `type: [string, 'null']` (the form the file already uses, for example `dataPolicy.verifiedOn`), not `nullable: true`. `minLength` and `maxLength` apply only to the string branch.
   The cleanup of the goldens to `null` also needs `components.schemas.PrivacyConsent.properties.policyVersion` to change from `type: string` to:
```yaml
        policyVersion:
          type: [string, 'null']
          maxLength: 64
          description: |
            The policy version the user was shown and accepted. `null` means no published policy
            was accepted; the backend treats that as not accepted.
```
   It stays in `required`. Otherwise the Draft 2020-12 validation in `verify-openapi-contract-examples.py` rejects the `null` goldens. The Worker doesn't read `privacyConsent.policyVersion` today [code: no reference in `backend/workers/src`].
   Add a `ModelConfigResponse` golden to `scripts/verify-openapi-contract-examples.py` with `policyVersion` read from `shared/privacy-policy-version.json` (`null` today), plus a negative case showing an empty string is rejected (PM decision (c): the contract-example check must cover it). The policy version is **not** added to generate responses in Sprint 6. #12 is not blocked (section 5.7). If the section 5.6 carrier is accepted, its `GenerateRequest.acceptedPolicyVersion` goes into the #26 A-3 openapi PR.

The contract-example check (`scripts/verify-openapi-contract-examples.py`) and Redocly lint must pass. Add one golden `GenerateResponse` example with `fallbackReason` and one without.

### 10.6 Planned contract addition: `spendCapResetsAt` (not Sprint 6; not part of the section 10.5 change; accepted by the PM, 2026-09-26)
- **Lands with** the P1 global-cap issue (section 11), in that issue's openapi PR.
- **Field:** an optional `GenerationMeta.spendCapResetsAt`, an RFC 3339 UTC timestamp (`...Z`). It's present only with `fallbackReason: "SPEND_CAP"`, and it's the earliest time a provider-backed generation can succeed again: the **latest** reset among the caps that tripped (device, global, or both).
- **Computed by the server,** because only the server knows which cap tripped. It's **absent when unknown** (for example, a ledger was unavailable).
- **Clients** treat absence as "no time shown". They make no extra `GET /v1/usage` call to fill it in.
- **Sprint 6** ships the no-time `SPEND_CAP` copy only.

## 11. Preconditions for turning on paid calls (hard; none are built in phase A)

Paid calls (any environment) may not be enabled until **all** of these are true:
1. **Overall application spending cap (founder prerequisite).** Enforced atomically in the Worker, in addition to the per-device daily cap. The founder sets the value and period; this record contains no figures.
   - **Fail-closed, explicitly:** the provider path is **not taken**, and the response falls back to the deterministic result with `fallbackReason: "SPEND_CAP"`, when **either** (a) the reservation would exceed the global cap, **or** (b) the global ledger can't be read or updated (Durable Object error, exception, timeout, or unexpected state). The same applies to the per-device ledger. The distinction is kept only in the server-side `fallbackCause` (`GLOBAL_CAP`, `GLOBAL_LEDGER_UNAVAILABLE`, `DEVICE_CAP`, `DEVICE_LEDGER_UNAVAILABLE`). No provider request is ever sent without a confirmed reservation in both ledgers.
   - *Proposed mechanism:* a singleton Durable Object ledger (`GlobalSpendLedger`, `getByName("global")`) with per-UTC-day totals, using the same reserve / reconcile / age API and attempt ids as the per-device ledger (#13).
   - **Check order for a paid call (decided 2026-09-26; accepted by the PM):**
     1. The configured model is on the allowlist and resolves to a price. If not, there's no ledger access and the response falls back with `PROVIDER_ERROR` (`MODEL_NOT_CONFIGURED` / `MODEL_NOT_ALLOWED`).
     2. Reserve the upper bound against the **per-device** ledger. If that's refused or fails, the global ledger is **never called**, and the response falls back with `SPEND_CAP`.
     3. Reserve the same upper bound against the **global** ledger. If that's refused or fails, **release the device reservation from step 2** (a known outcome, since no provider call was made), then fall back with `SPEND_CAP`. If the release itself fails, the device reservation stays reserved and ages under section 12, which only over-counts.
     
     *Why this order:* both reservations need the model's price, so step 1 comes first. Checking the device before the global ledger means a device that's already over its cap is rejected without touching the single global ledger, the one shared hot object. That reduces contention and stops one abusive device from repeatedly tying up global headroom. Both ledgers fail closed.
   - Reservations in both ledgers reconcile together under the same attempt id. Unknown outcomes age to spent after 24 h in **both** (section 12). The cap comes from a variable (`GLOBAL_DAILY_CAP_USD`, value set by the founder and recorded privately). **Missing, invalid, or zero means no paid calls** (fail-closed, unlike today's per-device `resolveSpendConfig`, which falls back to sample defaults). One object serialises every paid attempt. That is acceptable at this product's traffic and is the point of the design.
   - *Backstop (founder action):* an OpenRouter per-key credit limit with auto top-up **off**. It currently isn't verified.
   - *Kill switch:* set the flag off (a configuration deploy) or set the global cap to zero. Either one stops paid attempts at the next request.
   - *Required tests (for the P1 issue):* cap reached → no provider call, `SPEND_CAP`; global ledger throws or times out → no provider call, `SPEND_CAP`; **a global refusal or failure releases the device reservation**; **a device over its cap never calls the global ledger** (spy); **unknown-outcome aging (24 h) applies to both reservations**; cap variable missing, invalid, or zero → no provider call; model not allowlisted or unpriced → neither ledger is called; concurrent attempts near the cap never exceed it.
   - *Planned contract addition (lands with this P1 issue, not Sprint 6):* `GenerationMeta.spendCapResetsAt`, as defined in section 10.6. The server computes it from the caps that tripped.
   - Why a global cap is needed: today's caps are per device token per day, and anyone holding the enrollment secret can mint tokens, so there's no ceiling across devices.
2. A founder-authorized application budget and a live model allowlist entry (section 7).
3. #13 and #14 merged (atomic reservation, aging, and a concurrency proof against real workerd with the real Durable Object binding), and #12 merged (allowlist, `/v1/models`).
4. Provider settings verified and dated (section 5.3), `dataPolicy.verifiedOn` set from that verification, and disclosure in the app (section 5.4).
5. The logging redaction in section 5.2 implemented in the real provider client.
6. A release decision per DevFlow (a production flag change is a release, and a founder decision when it adds ongoing cost).

## 12. Unknown-outcome aging (re-recorded publicly; internal D-34, ACCEPTED 2026-09-18)

- One atomic upper-bound reservation per paid attempt (max input tokens × input price + max output tokens × output price). It's released only on reconciliation to a known cost. A failed reconciliation never releases funds.
- **Unknown outcomes** (timeout, interrupted request, failed reconciliation) stay reserved. They're reconciled from the provider's per-request usage record when it's available, and **count as fully spent 24 hours after the reservation**.
- **Why 24 h (confirmed, agreeing with the PM):** it's the accepted D-34 value, repeated in openapi `UsageResponse.unresolvedAttempts` ("ages to 'spent' after 24 h") and PRD §9.6. It's four orders of magnitude longer than any in-flight attempt (≤ 8 s provider timeout, 15 s client). It's longer than the provider logging delays the PM cited (an OpenRouter status incident of about 4 h 48 min; not independently verified by the Architect). And it only errs toward over-counting.
- **How an unknown outcome learns its cost:** through a `CostSource` interface. Live, this is OpenRouter's per-request generation record looked up by generation id (VF-13, documentation checked 2026-09-18). Phase A uses a mock that returns known, unknown, or error deterministically. Reconciliation is attempted lazily at each ledger access for that device (the PRD says "at the next ledger read"), at increasing intervals, until the entry is known or 24 h. A timed-out attempt that never received a generation id can't be looked up, so it ages to spent at 24 h. An aged or unreconciled reservation counts against the ledger day **in which it was reserved**.

## 13. Open items (not decided here)

| # | Item | Owner |
|---|---|---|
| 1 | Live model: **decided**, `typesafe/jev-1.13` (founder, 2026-09-26; section 7.1). Decided by the CTO (2026-09-26): call it through the Decisions API, with the real client and the `/api/v1/systemone` fallback deferred to the paid-activation issue; the soft threshold is informational only. Still open: the budget (internal D-09, Proposed, not authorized) | CTO + founder |
| 2 | How the Worker learns the stored accepted policy version on image-free generate (recommended: optional `GenerateRequest.acceptedPolicyVersion`, section 5.6). Until decided, the provider path is unreachable outside tests. | CTO (PM consulted, #11 owner) |
| 3 | Global cap value and period, the OpenRouter key limit, auto top-up off | Founder |
| 4 | Production Durable Object migration deploy (#13): founder go-ahead, via a CE deploy packet | Founder (CE packet) |

Follow-up task (not a decision): Designer copy for the three approved `fallbackReason` values. Unknown values use the `PROVIDER_ERROR` copy.

## 14. Relationship to earlier decisions

This record builds on these internal decisions (private historical log, IDs cited for traceability only): D-03 (model selects only from a deterministic shortlist), D-04 (id grounding, P0), D-18 (deterministic engine is the permanent fallback), D-20 (ledger is the only backend state; soft threshold and hard cap), D-34 (reservation and 24 h aging, re-recorded in section 12), D-37, D-47 (Durable Object pattern), D-67 and D-68 (privacy claims; section 4.3 applies D-68 option C to the provider path only). It does not continue the D-nn numbering, because that log lives in a private historical repository. New public decisions use `docs/architect/decisions/NNNN-<slug>.md` (CTO, 2026-09-26).

## 15. Consequences

- **Easier:** the provider path can be built and evaluated with zero provider spend, with a contract the iOS app can already decode. The privacy surface is small and testable.
- **Harder:** rationales use no free-text or profile context in phase A (PM decisions (a) and (e)), so eval quality with the mock and early live runs understates what profile inputs could add. The provider path stays off everywhere until #11 publishes a real policy version (served `null` today) and the request carrier (CTO) is decided. The global cap and live settings are extra work before any paid activation.
- **Follow-ups:** `check-provider-flag-off.py` and the environment allowlist (section 9); the policy-version constant (`null`), Swift mirror (`nil`), parity check, and fixture and golden cleanup (section 5.6, in #12); the openapi PR (section 10.5); the prompt registry and hash test; `buildProviderPayload` and its tests; the provider-output validator wrapper around `runStage4`; the flag parser and tests; the provider client's error redaction and timeout; the mock-provider eval arm (A-4); a new P1 issue "Global application spend cap" gating paid enablement.

## Decision notes (CTO, 2026-09-26)
- **Accepted** as written, with two redactions for the public repo: the first-comparison budget appears only as "internal D-09, Proposed, not authorized", and the recorded model candidate appears only as "one candidate recorded internally; none approved". This record contains no dollar figures, cap values, or provider model slugs. (`mock/stylist-v0` is a mock identifier, not a provider slug.)
- **Path and numbering:** `docs/architect/decisions/0001-openrouter-styling-phase-a.md`. `NNNN-<slug>.md` replaces the D-nn numbering for new public decisions.
- **Flag (section 9):** the SOP-004 item 18 deviations are accepted for phase A, to be revisited before any live production enablement. No flag ADR is split out.
- **Ledger (#13):** 31-day retention of per-device day records is accepted. The per-device Durable Object and its migration are **authorized to build and merge**. The **production migration deploy needs the founder's go-ahead through a CE deploy packet**. Removing the unused `USAGE_LEDGER` KV binding or namespace is a later, separate release decision.
- **QA (process note):** the spend trigger for Opus QA is a Sprint 6 override of approved SOP-001 v1.1 (to be raised at the retro; an SOP-001 amendment is proposed). Opus 5.5 satisfies SOP-001's "frontier model of the same family" wording. The Architect security check and QA may both use Opus 5.5, on the condition that QA runs in its own session and reaches its own verdict.
- **#14 test runtime:** `@cloudflare/vitest-plugin` (acceptance criteria tracked in #14). This doesn't change any decision here.

## Review
Review when the founder authorizes a paid budget, before any live flag value is added, and at each milestone boundary (model and provider re-check cadence).

---

## Amendment log
_(Append dated amendments here. Never edit the sections above once the status is Approved.)_
- 2026-09-26: PM decisions (a)–(e) folded into the body while still Proposed, before CTO review: summaryText and freeTextNote not sent; one canonical policy-version constant with parity check and a strict accepted-equals-served rule (supersedes "serve null"; value pending the PM because the code evidence is ambiguous); `/v1/models` alone satisfies #12 AC 2; `fallbackReason` values approved, plus a server-only `fallbackCause`; profile on generate out of Sprint 6.
- 2026-09-26: CTO accepted this record (status Accepted). Renamed to `0001-openrouter-styling-phase-a.md`; NNNN numbering replaces D-nn for new public decisions. Redacted the first-comparison budget and the recorded model candidate, and removed the remaining figures (zero spend now written in words; soft-threshold percentages removed). Flag deviations accepted for phase A, with no ADR-002. 31-day ledger retention accepted. DO migration authorized to build and merge; the production migration deploy needs the founder's go via a CE deploy packet; KV removal is a later release decision. QA process note added. Details in "Decision notes".
- 2026-09-26: Section 9 security amendment (found by the CE). The live production deploy uses the top-level config, where `ENVIRONMENT` is unset, so the `ENVIRONMENT === "production"` force-off was inert. Replaced with an exact non-production allowlist (`staging`): unset or unknown counts as production, which means off. Added the required environment tests, `scripts/check-provider-flag-off.py` (Repo Checks plus CE pre-deploy strict mode), a post-deploy `wrangler versions view --json` confirmation, and explicit "off" in every live config block (private). No flag field on `/health`. This is the first read of `ENVIRONMENT` in the Worker.
- 2026-09-26: Section 11 made explicitly fail-closed: cap reached **or** global (or device) ledger unreadable or unwritable means no provider path and `fallbackReason: "SPEND_CAP"`. Added ledger-unavailable `fallbackCause` values and the P1 test list. Section 11 contains no figures, so the PM can use it as the P1 issue body.
- 2026-09-26: Section 11 check order decided: allowlist and price, then the per-device reservation, then the global reservation, releasing the device reservation if the global step fails; both fail closed. This replaces the earlier global-first order. Added tests for the release on global failure, no global call for a device over its cap, and 24 h aging of both reservations.
- 2026-09-26: Planned `GenerationMeta.spendCapResetsAt` recorded in section 10.6 and section 11. It lands with the P1 global-cap issue and isn't part of the Sprint 6 section 10.5 change. Sprint 6 ships the no-time copy.
- 2026-09-26: Final PM policy-version decision. The canonical constant is `null` ("no policy published"; Worker `CURRENT_PRIVACY_POLICY_VERSION = null`, Swift `nil`, `/v1/models` `policyVersion: null`), chosen by the PM over a sentinel string. Accepted if and only if the served version is a non-empty string and the stored version equals it exactly, so the provider path is off everywhere until #11. #12 is not blocked. Parity check updated. Fixture changes to `test-fixture-policy` and goldens to `null`. Section 10.5 now shows the OpenAPI 3.1 nullable schemas for `ModelConfigResponse.policyVersion` and `PrivacyConsent.policyVersion`. The "pending PM" open item is removed. Supersedes the policy-version text of the first 2026-09-26 PM line.
- 2026-09-26: The PM accepted the section 11 check order and the planned `spendCapResetsAt` (section 10.6).
- 2026-09-26: #14 test runtime changed from `@cloudflare/vitest-pool-workers` to `@cloudflare/vitest-plugin` (acceptance criteria in #14). Section 11 item 3 now requires the concurrency proof against real workerd with the real Durable Object binding.
- 2026-09-26: Founder decision (relayed by the CTO): the intended live model is `typesafe/jev-1.13`, recorded as the config value `STYLIST_PRIMARY_MODEL` plus a #12 allowlist entry, both added only at paid activation (new section 7.1). `typesafe/jev-router` is rejected because its price is unpublished, which is incompatible with the reservation and the section 11 price check. The Sprint 6 posture is unchanged: mock only, eligible only in `staging`, no OpenRouter spend, flag off in production, `verifiedOn` null. This supersedes the "no provider model slugs" line in the Decision notes for this one founder-chosen slug. No prices or figures are recorded here.
- 2026-09-26: Typed-decision fit (section 7.1.1 to 7.1.5). Public docs say the model runs on the Decisions API, not chat completions, and returns typed answers only, with no free text. Section 6 step 1 (provider output schema) is replaced for this shape by a Decisions-answer check and a mapping to assignments. Model-written text checks don't apply. Rationale is composed on the server with the existing `templateRationale`. The client contract (`Rationale`, `OutfitAssignment`, `GenerationMeta`, section 10.5) is unchanged. New server-only cause: `OUTPUT_MODEL_MISMATCH`. The phase A mock emits the same Decisions shape. Paid-activation items (real client, price-check semantics with zero as a valid price, cost bound, confidence gating) are listed in section 7.1.6 for a later issue.
- 2026-09-26: CTO decisions on the model fit. (1) The Decisions API is accepted; the real client and the `/api/v1/systemone` fallback are deferred to the paid-activation issue. (2) The soft threshold (D-20) is informational only, surfaced in the usage summary and telemetry; only the hard cap triggers the deterministic fallback, and there is no secondary model. (3) Departures from the PRD section 10.1 model-selection procedure are acknowledged: one model instead of a candidate comparison, no vision, no `response_format`, and a 32K context. (4) The founder-chosen slug supersedes the earlier "no provider model slugs" note. Section 7 and section 13 item 1 updated to match.
- 2026-09-26: #12 contract detail (Architect, answering the Backend Engineer). `ModelConfigResponse.primary` stays required and becomes `oneOf: [ModelDescriptor, {type: 'null'}]`, served as `null` when no allowlisted primary is configured; `secondary` gets the same treatment only if it is currently required and non-null. `promptVersion` on `/v1/models` serves `"none"` until A-3 wires the A-1 prompt registry. `dataPolicy` serves `excludesTrainingProviders: true`, `verifiedOn: null`, `note: null`. Contract goldens cover both the configured (mock) and unconfigured cases. Raw environment values are never echoed.
