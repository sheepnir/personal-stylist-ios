# Jev / GPT-5.6 Luna comparison

Issue #116 adds a locally persisted model picker to Profile and the outfit board.
Changing the picker marks the board settings as changed. Update outfit uses the
same current wardrobe, anchor, locks and context without Try another exclusions.
Requests call only the selected model. The board names the original generating
model; swaps retain their own provenance independently.

Luna requires its own text-only consent. Jev consent does not authorize OpenAI.
Both models receive the same allowlisted attributes and choose from complete
validated candidates. Luna returns a strict JSON choice; no generated prose is
rendered. Jev retains its existing probability/confidence checks. Luna does not
invent a comparable confidence score. This is a comparison of the two complete
selection paths, not calibrated confidence or a claim of better quality.

Luna uses OpenRouter Chat Completions with an OpenAI provider allowlist, data
collection denied, provider fallback disabled, no retries, low reasoning effort,
and 1,024 output tokens. Endpoint pricing is fetched for each attempt. A conservative
bounded-input reservation plus the output limit uses the existing device/global
ledger and total cap. All existing deployment/device gates remain; the additional
LUNA_COMPARISON=enabled server switch defaults off.

References checked:
- https://developers.openai.com/api/docs/models/gpt-5.6-luna
- https://openrouter.ai/docs/guides/features/structured-outputs
- https://openrouter.ai/api/v1/models/openai/gpt-5.6-luna/endpoints

## Validation

- Worker typecheck and full suite: 516 tests pass.
- Independent QA adds 13 real-ledger tests proving caps survive model switching,
  endpoint isolation, and model-specific consent in both directions.
- Full iOS suite: 401 tests, one Keychain skip, zero failures, successful exit.
- Policy parity, copy, asset, wear and sample-literal checks pass.
- Independent review corrected swap attribution and added a versioned full-request
  golden; re-review found no remaining blockers.

No live Luna call or physical-device acceptance is claimed. Provider policy
verification and explicit activation approval remain release gates.
