/**
 * Run eval suite: deterministic arm via generateLocal or rankAlternatives.
 * Multi-step alternatives_swap_rerank (M1-F05-07) supported; model arms deferred (M0-09).
 */

import {
  isAlternativesProblem,
  rankAlternatives,
  type AlternativesRequest,
  type AlternativesResponse,
} from "../alternatives/rankAlternatives.js";
import { generateLocal } from "../pipeline/generateLocal.js";
import type { OutfitAssignment, Slot } from "../types.js";
import {
  alternativesFingerprint,
  assertOrderDiffers,
  compareAlternativesStep,
  compareExpected,
  resultFingerprint,
} from "./compare.js";
import {
  alternativesBaseFromScenario,
  applySwapToAssignments,
  defaultFixturesRoot,
  isAlternativesSwapRerankScenario,
  isOutfitTask,
  loadScenarioById,
  requestFromScenario,
  resolveScenarioIds,
  type ScenarioFile,
} from "./scenarios.js";
import { promptVersionForEvalArm } from "./promptVersion.js";
import type {
  EvalReport,
  RunEvalOptions,
  ScenarioEvalResult,
} from "./types.js";

const DEFERRED_MSG = "model arm deferred until M0-09";

function normalizeModels(models: string[]): {
  runDeterministic: boolean;
  deferred: string[];
  noneOnly: boolean;
} {
  const parts = models
    .flatMap((m) => m.split(","))
    .map((m) => m.trim())
    .filter(Boolean);
  const deferred: string[] = [];
  let runDeterministic = false;
  let noneOnly = false;
  for (const m of parts) {
    const lower = m.toLowerCase();
    if (lower === "deterministic") runDeterministic = true;
    else if (lower === "none") noneOnly = true;
    else deferred.push(m);
  }
  if (noneOnly && !runDeterministic && deferred.length === 0) {
    return { runDeterministic: false, deferred: [], noneOnly: true };
  }
  return { runDeterministic, deferred, noneOnly: false };
}

function buildAlternativesRequest(
  scenario: ScenarioFile,
  fixturesRoot: string,
  slot: Slot,
  currentAssignments: OutfitAssignment[],
  limit?: number,
): AlternativesRequest {
  const base = alternativesBaseFromScenario(scenario, fixturesRoot);
  return {
    slot,
    currentAssignments,
    wardrobe: base.wardrobe,
    profile: base.profile,
    context: base.context,
    sets: base.sets,
    limit,
    options: base.options,
    accessoryPolicy: base.options?.accessoryPolicy,
    asOfDate: base.asOfDate,
  };
}

function evaluateAlternativesSwapRerank(
  scenario: ScenarioFile,
  fixturesRoot: string,
): { result: ScenarioEvalResult; fingerprint: string } {
  const steps = scenario.steps ?? [];
  const failures: string[] = [];
  const step1Spec = steps.find((s) => s.step === 1) ?? steps[0];
  const step2Spec = steps.find((s) => s.step === 2) ?? steps[1];

  if (!step1Spec || !step2Spec) {
    return {
      result: {
        scenarioId: scenario.id,
        title: scenario.title,
        task: scenario.task,
        model: "deterministic",
        passed: false,
        expectedClassification: "alternatives",
        actualClassification: "unknown",
        exactOutfitMatch: null,
        failures: ["alternatives_swap_rerank fixture missing steps[1] and steps[2]"],
        actualSummary: {},
        promptVersion: promptVersionForEvalArm("deterministic"),
      },
      fingerprint: "missing-steps",
    };
  }

  // --- Step 1: FOOTWEAR (or fixture slot) alternatives ---
  const step1Req = buildAlternativesRequest(
    scenario,
    fixturesRoot,
    step1Spec.request.slot as Slot,
    step1Spec.request.currentAssignments,
    step1Spec.request.limit,
  );
  const step1Raw = rankAlternatives(step1Req);
  if (isAlternativesProblem(step1Raw)) {
    failures.push(
      `step1 Problem: ${step1Raw.code} — ${step1Raw.detail ?? step1Raw.title}`,
    );
    return {
      result: {
        scenarioId: scenario.id,
        title: scenario.title,
        task: scenario.task,
        model: "deterministic",
        passed: false,
        expectedClassification: "alternatives",
        actualClassification: "problem",
        exactOutfitMatch: null,
        failures,
        actualSummary: { problemCode: step1Raw.code },
        promptVersion: promptVersionForEvalArm("deterministic"),
      },
      fingerprint: JSON.stringify({ problem: step1Raw.code }),
    };
  }
  const step1 = step1Raw as AlternativesResponse;
  compareAlternativesStep(
    { label: "step1", expected: step1Spec.expected, actual: step1 },
    failures,
  );

  // Apply swap to assignments (D-33 path — do not trust stale candidateSet)
  const swap = step1Spec.expected.apply_swap;
  let postSwapAssignments: OutfitAssignment[];
  if (swap) {
    const base = alternativesBaseFromScenario(scenario, fixturesRoot);
    postSwapAssignments = applySwapToAssignments(
      step1Spec.request.currentAssignments,
      swap,
      base.wardrobe,
    );
  } else if (step1Spec.expected.post_swap_assignments) {
    postSwapAssignments = step1Spec.expected.post_swap_assignments;
  } else {
    postSwapAssignments = step2Spec.request.currentAssignments;
  }

  // A-STALE baseline: TOP (or step2 slot) ranking against *pre-swap* assignments
  const step2Slot = step2Spec.request.slot as Slot;
  const preSwapTopRaw = rankAlternatives(
    buildAlternativesRequest(
      scenario,
      fixturesRoot,
      step2Slot,
      step1Spec.request.currentAssignments,
      step2Spec.request.limit ?? 8,
    ),
  );
  const preSwapTopIds = isAlternativesProblem(preSwapTopRaw)
    ? []
    : preSwapTopRaw.alternatives.map((a) => a.garmentId);

  // --- Step 2: alternatives against post-swap assignments ---
  const step2Req = buildAlternativesRequest(
    scenario,
    fixturesRoot,
    step2Slot,
    postSwapAssignments,
    step2Spec.request.limit,
  );
  const step2Raw = rankAlternatives(step2Req);
  if (isAlternativesProblem(step2Raw)) {
    failures.push(
      `step2 Problem: ${step2Raw.code} — ${step2Raw.detail ?? step2Raw.title}`,
    );
    return {
      result: {
        scenarioId: scenario.id,
        title: scenario.title,
        task: scenario.task,
        model: "deterministic",
        passed: false,
        expectedClassification: "alternatives",
        actualClassification: "problem",
        exactOutfitMatch: null,
        failures,
        actualSummary: {
          problemCode: step2Raw.code,
          step1RankedIds: step1.alternatives.map((a) => a.garmentId),
          step1EmptyReason: step1.emptyReason ?? null,
        },
        promptVersion: promptVersionForEvalArm("deterministic"),
      },
      fingerprint: alternativesFingerprint(step1, {
        slot: step2Slot,
        alternatives: [],
        emptyReason: null,
      }),
    };
  }
  const step2 = step2Raw as AlternativesResponse;
  compareAlternativesStep(
    { label: "step2", expected: step2Spec.expected, actual: step2 },
    failures,
  );

  // expected_summary soft checks (ranked + exclude + emptyReason)
  const summary = scenario.expected_summary;
  if (summary?.step2_rankedGarmentIds?.length) {
    const got = step2.alternatives.map((a) => a.garmentId);
    if (JSON.stringify(got) !== JSON.stringify(summary.step2_rankedGarmentIds)) {
      failures.push(
        `expected_summary.step2_rankedGarmentIds: want ${JSON.stringify(summary.step2_rankedGarmentIds)}, got ${JSON.stringify(got)}`,
      );
    }
  }
  if (summary && "step2_emptyReason" in summary) {
    const want = summary.step2_emptyReason ?? null;
    const got = step2.emptyReason ?? null;
    if (want !== got) {
      failures.push(
        `expected_summary.step2_emptyReason: want ${String(want)}, got ${String(got)}`,
      );
    }
  }
  if (summary?.step2_must_exclude?.length) {
    const gotSet = new Set(step2.alternatives.map((a) => a.garmentId));
    for (const id of summary.step2_must_exclude) {
      if (gotSet.has(id)) {
        failures.push(`expected_summary.step2_must_exclude present: ${id}`);
      }
    }
  }

  // A-STALE: post ranking must differ from pre-swap ranking for the same slot
  const postIds = step2.alternatives.map((a) => a.garmentId);
  const orderMeta = step2Spec.expected.order_vs_pre_swap_top;
  let aStale = false;
  if (orderMeta?.assert_order_differs !== false) {
    // Prefer live pre-swap ranking; fall back to fixture pre_swap list if live failed
    const preIds =
      preSwapTopIds.length > 0
        ? preSwapTopIds
        : (orderMeta?.pre_swap_rankedGarmentIds ?? []);
    aStale = assertOrderDiffers("step2", preIds, postIds, failures);
  }

  const fingerprint = alternativesFingerprint(step1, step2);
  return {
    result: {
      scenarioId: scenario.id,
      title: scenario.title,
      task: scenario.task,
      model: "deterministic",
      passed: failures.length === 0,
      expectedClassification: "alternatives",
      actualClassification: "alternatives",
      exactOutfitMatch: null,
      failures,
      actualSummary: {
        step1RankedIds: step1.alternatives.map((a) => a.garmentId),
        step2RankedIds: postIds,
        step1EmptyReason: step1.emptyReason ?? null,
        step2EmptyReason: step2.emptyReason ?? null,
        aStaleOrderDiffers: aStale,
      },
      promptVersion: promptVersionForEvalArm("deterministic"),
    },
    fingerprint,
  };
}

function evaluateGenerateOnce(
  scenarioId: string,
  fixturesRoot: string,
): { result: ScenarioEvalResult; fingerprint: string } {
  const scenario = loadScenarioById(fixturesRoot, scenarioId);
  if (!scenario.expected) {
    return {
      result: {
        scenarioId: scenario.id,
        title: scenario.title,
        task: scenario.task,
        model: "deterministic",
        passed: false,
        expectedClassification: "unknown",
        actualClassification: "unknown",
        exactOutfitMatch: null,
        failures: ["scenario missing expected (not a generate fixture)"],
        actualSummary: {},
        promptVersion: promptVersionForEvalArm("deterministic"),
      },
      fingerprint: "missing-expected",
    };
  }
  const request = requestFromScenario(scenario, fixturesRoot);
  const raw = generateLocal(request);
  const compared = compareExpected(
    scenario.id,
    scenario.expected,
    raw,
    "deterministic",
  );
  return {
    result: {
      ...compared,
      title: scenario.title,
      task: scenario.task,
    },
    fingerprint: resultFingerprint(raw),
  };
}

function evaluateOnce(
  scenarioId: string,
  fixturesRoot: string,
): { result: ScenarioEvalResult; fingerprint: string } {
  const scenario = loadScenarioById(fixturesRoot, scenarioId);
  if (isAlternativesSwapRerankScenario(scenario)) {
    return evaluateAlternativesSwapRerank(scenario, fixturesRoot);
  }
  return evaluateGenerateOnce(scenarioId, fixturesRoot);
}

export function runEval(options: RunEvalOptions): EvalReport {
  const fixturesRoot = options.fixturesRoot ?? defaultFixturesRoot();
  const repeats = Math.max(1, options.repeats ?? 1);
  const taskFilter = options.taskFilter ?? isOutfitTask;
  const scenarioIds = resolveScenarioIds(
    fixturesRoot,
    options.scenarios,
    taskFilter,
  );

  const { runDeterministic, deferred, noneOnly } = normalizeModels(
    options.models,
  );
  const deferredMessages: string[] = [];
  for (const m of deferred) deferredMessages.push(`${m}: ${DEFERRED_MSG}`);
  if (noneOnly) deferredMessages.push("none: no model arms selected");

  const results: ScenarioEvalResult[] = [];

  if (runDeterministic) {
    for (const id of scenarioIds) {
      const fingerprints: string[] = [];
      let last: ScenarioEvalResult | null = null;
      for (let i = 0; i < repeats; i++) {
        const { result, fingerprint } = evaluateOnce(id, fixturesRoot);
        fingerprints.push(fingerprint);
        last = result;
      }
      if (!last) continue;
      let deterministic: boolean | null = null;
      if (repeats > 1) {
        deterministic = fingerprints.every((f) => f === fingerprints[0]);
        if (!deterministic) {
          last = {
            ...last,
            passed: false,
            failures: [
              ...last.failures,
              `determinism failed across ${repeats} repeats`,
            ],
          };
        }
      }
      results.push({ ...last, deterministic, repeats });
    }
  }

  return {
    models: options.models,
    scenarios: scenarioIds,
    repeats,
    passed: results.filter((r) => r.passed).length,
    failed: results.filter((r) => !r.passed).length,
    deferredModels: deferred,
    deferredMessages,
    results,
  };
}

export function evaluateScenario(
  scenarioId: string,
  fixturesRoot?: string,
): ScenarioEvalResult {
  const root = fixturesRoot ?? defaultFixturesRoot();
  const { result } = evaluateOnce(scenarioId, root);
  return { ...result, deterministic: null, repeats: 1 };
}
