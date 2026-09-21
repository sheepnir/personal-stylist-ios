# @personal-stylist/outfit-engine

Deterministic **Stage 1–4 outfit engine** + **eval harness (M0-17)** + **alternatives (M0-21)** + **local generation (M0-20)**.

- **No network, no OpenRouter, no secrets**
- Pure functions + Vitest against `fixtures/`
- Contract: `docs/openapi.yaml` (design notes are internal and not part of this repository)

## Layout

```
src/
  types.ts
  index.ts          # Main exports: runStage1, runStage2, runBuilder, runStage4
  stage1/
    hardFilter.ts   # runStage1(input) → Stage1Result | Stage1Problem
    prechecks.ts
    filters.ts
    ladder.ts
  stage2/
    runStage2.ts    # runStage2(stage1, input, config?) → Stage2Result
    score.ts
    combination.ts
    shortlist.ts
    sets.ts
    config.ts
    components/
  stage3/
    runBuilder.ts   # runBuilder(stage2, input, config?) → BuilderResult
    place.ts
    combination.ts
    layers.ts
    order.ts
    rationaleTemplate.ts
    config.ts
  stage4/
    runStage4.ts    # runStage4(input) → Stage4Result
  alternatives/
    rankAlternatives.ts  # rankAlternatives(input) → AlternativesResult
    reasonTemplate.ts
    toStage1SwapInput.ts
  pipeline/
    generateLocal.ts     # Full generate pipeline
  local/
    server.ts            # Local HTTP server (:8787)
    cli.ts               # CLI for local generation
    validation.ts
  eval/
    cli.ts               # Eval harness CLI
    run.ts
    compare.ts
    scenarios.ts
    report.ts
  shared/
    membership.ts        # Set membership helpers
    combinationRules.ts  # Shared combination rule helpers
  utils/
    dates.ts             # Date utilities
config/scoring.defaults.json
tests/stage1/*.test.ts
tests/stage2/*.test.ts
tests/stage3/*.test.ts
tests/stage4/*.test.ts
tests/local/*.test.ts
tests/alternatives/*.test.ts
```

## Eval harness (M0-17)

```bash
npm run eval -- run --models deterministic --scenarios all --repeats 1
```

Soft-compares fixture `expected` (complete outfit / gap / problem_code). Non-deterministic `--models` are deferred until M0-09.

## Run tests

```bash
cd backend/outfit-engine
npm install
npm test          # vitest run (non-watch) — preferred
npm run test:ci   # same as npm test
```

**Do not run bare `vitest`** — that enters watch mode and hangs CI/agents. Use `npm test` or `npm run test:ci`. For local iteration only: `npm run test:watch`.

Fixtures are loaded from `../../fixtures/` (wardrobe + T2 scenarios).

## Public API

```ts
import {
  runStage1,
  runStage2,
  runBuilder,
  runStage4,
  generateLocal,
  rankAlternatives,
  isAlternativesProblem,
  isLocalProblem,
  withWeights,
} from "@personal-stylist/outfit-engine";

// Stage 1: Hard filters
const stage1 = runStage1({
  wardrobe,
  context,
  anchorGarmentId,
  lockedAssignments,
  options: { requireSlots: ["TOP", "BOTTOM", "FOOTWEAR"] },
  profile: { activeRules },
  sets,
});

// Stage 2: Scoring and shortlisting
if (stage1.ok) {
  const stage2 = runStage2(stage1, {
    wardrobe,
    context,
    profile: { activeRules },
    sets,
    boldness: "SLIGHT_STRETCH",
    options: { candidatesPerSlot: 8 },
  });

  // Stage 3: Deterministic builder
  if (stage2.ok) {
    const builder = runBuilder(stage2, input, config);

    // Stage 4: Validation
    if (builder.ok) {
      const validation = runStage4({ ...input, assignments: builder.assignments });
    }
  }
}

// Full pipeline: generateLocal
const result = generateLocal(input);

// Alternatives
const alternatives = rankAlternatives({
  slot,
  currentAssignments,
  wardrobe,
  profile,
  context,
});
```

Combination DISLIKE pairs are **not** applied in Stage 1 (D-26); Stage 2 excludes partners that complete a forbidden pair with fixed pieces only.

## Local HTTP server (M0-20, M0-21)

```bash
npm run serve:local    # Start server on :8787
npm run generate:local # CLI generate
```

- `POST /v1/outfit/generate` — Full outfit generation (contract: `docs/openapi.yaml`)
- `POST /v1/outfit/alternatives` — Alternatives for a slot (contract: `docs/openapi.yaml`)

Locked/anchor slot → **200** + `emptyReason: LOCK_FIXED`. No OpenAPI mutate; no OpenRouter.

### Security posture (#181)

The local bridge is a **development-only** convenience for the Simulator and is
intentionally **unauthenticated**. This is acceptable only because it:

- binds `127.0.0.1` exclusively (loopback; not reachable off the host);
- makes **zero** outbound network calls and never touches OpenRouter or secrets;
- runs the deterministic engine only, on request payloads supplied locally.

Do **not** expose it beyond loopback: never bind `0.0.0.0`, port-forward it,
tunnel it, or run it on a shared/CI host reachable by others. The public,
authenticated surface is the Cloudflare Worker (`backend/workers`), which
requires a device-token `Bearer` and enforces validation, image rejection, and
rate limits. If the bridge ever needs to leave loopback, add device-token auth
to `src/local/server.ts` first.

