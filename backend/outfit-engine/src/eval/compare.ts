/**
 * Compare fixture `expected` against generateLocal / rankAlternatives output.
 */

import {
  isLocalProblem,
  type GenerateLocalOutput,
  type LocalGenerateResponse,
  type LocalProblemBody,
} from "../pipeline/generateLocal.js";
import type { AlternativesResponse } from "../alternatives/rankAlternatives.js";
import type { AlternativesScenarioStep, ScenarioExpected } from "./scenarios.js";
import type { OutcomeClassification, ScenarioEvalResult } from "./types.js";
import { promptVersionForEvalArm } from "./promptVersion.js";

function assignmentMaps(result: LocalGenerateResponse): {
  outfit: Record<string, string | null>;
  gaps: Record<string, string>;
  filledIds: string[];
} {
  const outfit: Record<string, string | null> = {};
  const gaps: Record<string, string> = {};
  const filledIds: string[] = [];
  for (const a of result.assignments) {
    if (a.slot === "ACCESSORY") {
      // ACCESSORY is multi-valued; still count ids for must_include (anchors / locks).
      if (a.garmentId) filledIds.push(a.garmentId);
      continue;
    }
    if (a.garmentId) {
      outfit[a.slot] = a.garmentId;
      filledIds.push(a.garmentId);
    } else {
      outfit[a.slot] = null;
      if (a.gapReason) gaps[a.slot] = a.gapReason;
    }
  }
  return { outfit, gaps, filledIds };
}

export function expectedClassification(
  expected: ScenarioExpected,
): OutcomeClassification {
  if (expected.gap?.problem_code) return "problem";
  if (expected.no_outfit_produced) return "problem";
  if (expected.kind === "gap") return "gap";
  if (expected.kind === "complete_outfit") return "complete";
  return "unknown";
}

export function actualClassification(
  actual: GenerateLocalOutput,
): OutcomeClassification {
  if (isLocalProblem(actual)) return "problem";
  const { gaps, filledIds } = assignmentMaps(actual);
  if (Object.keys(gaps).length > 0) return "gap";
  if (filledIds.length > 0) return "complete";
  return "unknown";
}

function compareComplete(
  expected: ScenarioExpected,
  actual: LocalGenerateResponse,
  failures: string[],
): void {
  const { outfit, filledIds } = assignmentMaps(actual);
  const filled = new Set(filledIds);

  for (const id of expected.must_include ?? []) {
    if (!filled.has(id)) failures.push(`must_include missing: ${id}`);
  }
  for (const id of expected.must_exclude_garment_ids ?? []) {
    if (filled.has(id)) {
      failures.push(`must_exclude_garment_ids present: ${id}`);
    }
  }
  for (const slot of expected.must_exclude_slots ?? []) {
    if (outfit[slot]) {
      failures.push(`must_exclude_slots filled: ${slot}=${outfit[slot]}`);
    }
  }
  const together = expected.must_exclude_together;
  if (together?.length === 2) {
    if (filled.has(together[0]) && filled.has(together[1])) {
      failures.push(
        `must_exclude_together both present: ${together[0]}, ${together[1]}`,
      );
    }
  }
  const pair = expected.combination_rule?.forbidden_pair;
  if (pair?.length === 2) {
    if (filled.has(pair[0]) && filled.has(pair[1])) {
      failures.push(
        `combination_rule forbidden pair both present: ${pair[0]}, ${pair[1]}`,
      );
    }
  }
  
  // Enforce exact complete_outfit IDs unless soft_ids flag is set
  if (expected.complete_outfit && !expected.soft_ids) {
    for (const [slot, expectedId] of Object.entries(expected.complete_outfit)) {
      const actualId = outfit[slot];
      if (!actualId) {
        failures.push(`complete_outfit slot empty: ${slot} (expected ${expectedId})`);
      } else if (actualId !== expectedId) {
        failures.push(
          `complete_outfit ${slot}: expected ${expectedId}, got ${actualId}`,
        );
      }
    }
  }

  // Check set_atomicity if present
  const setCheck = expected.set_atomicity;
  if (setCheck?.required_together?.length === 2) {
    const [id1, id2] = setCheck.required_together;
    const has1 = filled.has(id1);
    const has2 = filled.has(id2);
    if (setCheck.any_result_using_either_uses_both) {
      if (has1 && !has2) {
        failures.push(`set_atomicity: has ${id1} but missing partner ${id2}`);
      }
      if (has2 && !has1) {
        failures.push(`set_atomicity: has ${id2} but missing partner ${id1}`);
      }
    }
  }

  const rationaleBits = [
    actual.rationale?.summary ?? "",
    ...(actual.rationale?.pairingNotes ?? []),
    ...(actual.rationale?.cautions ?? []),
  ].join("\n");
  const mention = expected.rationale_must_mention;
  if (Array.isArray(mention)) {
    for (const needle of mention) {
      if (typeof needle === "string" && !rationaleBits.includes(needle)) {
        failures.push(`rationale_must_mention missing: ${needle}`);
      }
    }
  }
  const cautionNeedle = expected.cautions_must_include_substring;
  if (typeof cautionNeedle === "string" && cautionNeedle.length > 0) {
    const cautions = actual.rationale?.cautions ?? [];
    const hit = cautions.some((c) =>
      c.toLowerCase().includes(cautionNeedle.toLowerCase()),
    );
    if (!hit) {
      failures.push(
        `cautions_must_include_substring missing: ${cautionNeedle} (got ${JSON.stringify(cautions)})`,
      );
    }
  }
  if (Object.prototype.hasOwnProperty.call(expected, "noAlternativeReason")) {
    const want = expected.noAlternativeReason;
    const got = actual.noAlternativeReason ?? null;
    if (want === true) {
      if (!got) {
        failures.push("expected noAlternativeReason to be set");
      }
    } else if (want === false || want === null) {
      if (got) {
        failures.push(`expected no noAlternativeReason, got ${got}`);
      }
    } else if (typeof want === "string" && want.length > 0) {
      if (!got || !got.includes(want)) {
        failures.push(
          `noAlternativeReason: want substring ${want}, got ${String(got)}`,
        );
      }
    }
  }

  // Check must_exclude_color_families if present
  if (expected.must_exclude_color_families?.length) {
    // This requires access to garment details to check colorPrimary.family
    // For now, document that this check requires garment catalog access
    // and defer implementation until needed for M0 gate
  }

  // Check formality_range if present
  if (expected.formality_range) {
    // This requires access to garment details to check formality scores
    // For now, document that this check requires garment catalog access
    // and defer implementation until needed for M0 gate
  }
  
  // Check layer_requirement if present
  if (expected.layer_requirement) {
    // This requires checking that required slots are filled for the temperature band
    // Deferred until needed for M0 gate
  }
}

function exactOutfitEquals(
  expected: Record<string, string> | undefined,
  outfit: Record<string, string | null>,
): boolean | null {
  if (!expected) return null;
  for (const [slot, id] of Object.entries(expected)) {
    if (outfit[slot] !== id) return false;
  }
  return true;
}

function compareGap(
  expected: ScenarioExpected,
  actual: LocalGenerateResponse,
  failures: string[],
): void {
  const { outfit } = assignmentMaps(actual);
  const slot = expected.gap?.slot;
  if (!slot) {
    failures.push("expected.gap.slot missing in fixture");
    return;
  }
  if (outfit[slot]) {
    failures.push(`expected gap at ${slot} but got garment ${outfit[slot]}`);
  }
  if (!Object.prototype.hasOwnProperty.call(outfit, slot)) {
    failures.push(`expected gap assignment at ${slot}`);
  }

  if (expected.complete_outfit_partial) {
    for (const [s, id] of Object.entries(expected.complete_outfit_partial)) {
      if (outfit[s] !== id) {
        failures.push(
          `complete_outfit_partial ${s}: want ${id}, got ${outfit[s] ?? "null"}`,
        );
      }
    }
  }
}

function compareProblem(
  expected: ScenarioExpected,
  actual: LocalProblemBody,
  failures: string[],
): void {
  const code = expected.gap?.problem_code;
  if (!code) {
    if (expected.no_outfit_produced) return;
    failures.push("expected problem_code missing in fixture");
    return;
  }
  if (actual.code !== code) {
    failures.push(`problem_code: want ${code}, got ${actual.code}`);
  }
}

export function compareExpected(
  scenarioId: string,
  expected: ScenarioExpected,
  actual: GenerateLocalOutput,
  model = "deterministic",
): Pick<
  ScenarioEvalResult,
  | "scenarioId"
  | "model"
  | "passed"
  | "expectedClassification"
  | "actualClassification"
  | "exactOutfitMatch"
  | "failures"
  | "actualSummary"
  | "promptVersion"
> {
  const expClass = expectedClassification(expected);
  const actClass = actualClassification(actual);
  const failures: string[] = [];
  let exactOutfitMatch: boolean | null = null;
  let actualSummary: ScenarioEvalResult["actualSummary"] = {};

  if (expClass === "problem") {
    if (!isLocalProblem(actual)) {
      failures.push("expected Problem / no outfit, got GenerateResponse");
      const maps = assignmentMaps(actual);
      actualSummary = { outfit: maps.outfit, gaps: maps.gaps };
    } else {
      actualSummary = { problemCode: actual.code };
      compareProblem(expected, actual, failures);
    }
  } else if (expClass === "gap") {
    if (isLocalProblem(actual)) {
      failures.push(`expected gapped outfit, got Problem ${actual.code}`);
      actualSummary = { problemCode: actual.code };
    } else {
      const maps = assignmentMaps(actual);
      actualSummary = { outfit: maps.outfit, gaps: maps.gaps };
      compareGap(expected, actual, failures);
    }
  } else if (expClass === "complete") {
    if (isLocalProblem(actual)) {
      failures.push(`expected complete outfit, got Problem ${actual.code}`);
      actualSummary = { problemCode: actual.code };
      exactOutfitMatch = false;
    } else {
      const maps = assignmentMaps(actual);
      actualSummary = { outfit: maps.outfit, gaps: maps.gaps };
      compareComplete(expected, actual, failures);
      exactOutfitMatch = exactOutfitEquals(
        expected.complete_outfit,
        maps.outfit,
      );
    }
  } else {
    failures.push(`unsupported expected.kind: ${String(expected.kind)}`);
  }

  return {
    scenarioId,
    model,
    passed: failures.length === 0,
    expectedClassification: expClass,
    actualClassification: actClass,
    exactOutfitMatch,
    failures,
    actualSummary,
    promptVersion: promptVersionForEvalArm(model),
  };
}

export function resultFingerprint(actual: GenerateLocalOutput): string {
  if (isLocalProblem(actual)) {
    return JSON.stringify({
      problem: true,
      code: actual.code,
      conflicts: actual.conflicts ?? null,
    });
  }
  const assignments = actual.assignments
    .map((a) => ({
      slot: a.slot,
      garmentId: a.garmentId ?? null,
      gapReason: a.gapReason ?? null,
    }))
    .sort((a, b) => a.slot.localeCompare(b.slot));
  return JSON.stringify({ problem: false, assignments });
}

/* -------------------------------------------------------------------------- */
/* Multi-step alternatives_swap_rerank compare (M1-F05-07)                      */
/* -------------------------------------------------------------------------- */

export interface AlternativesStepCompareInput {
  label: string;
  expected: AlternativesScenarioStep["expected"];
  actual: AlternativesResponse;
  /** Soft: require expected ranked ids as exact list (preferred) or ordered prefix. */
  rankedMode?: "exact" | "prefix";
}

/**
 * Soft-pass compare for one alternatives step.
 * Core: emptyReason, must_exclude_ids absent, rankedGarmentIds (exact preferred).
 * Scores checked within tolerance only when fixture provides them (never invent).
 */
export function compareAlternativesStep(
  input: AlternativesStepCompareInput,
  failures: string[],
): void {
  const { label, expected, actual } = input;
  const mode = input.rankedMode ?? "exact";
  const rankedIds = actual.alternatives.map((a) => a.garmentId);
  const rankedSet = new Set(rankedIds);

  const wantEmpty = expected.emptyReason ?? null;
  const gotEmpty = actual.emptyReason ?? null;
  if (wantEmpty !== gotEmpty) {
    failures.push(
      `${label} emptyReason: want ${String(wantEmpty)}, got ${String(gotEmpty)}`,
    );
  }

  for (const id of expected.must_exclude_ids ?? []) {
    if (rankedSet.has(id)) {
      failures.push(`${label} must_exclude present: ${id}`);
    }
  }

  const wantRanked = expected.rankedGarmentIds;
  if (wantRanked && wantRanked.length > 0) {
    if (mode === "exact") {
      if (JSON.stringify(rankedIds) !== JSON.stringify(wantRanked)) {
        failures.push(
          `${label} rankedGarmentIds: want ${JSON.stringify(wantRanked)}, got ${JSON.stringify(rankedIds)}`,
        );
      }
    } else {
      // Soft prefix: expected order is a prefix of actual (or exact).
      const prefix = rankedIds.slice(0, wantRanked.length);
      if (JSON.stringify(prefix) !== JSON.stringify(wantRanked)) {
        failures.push(
          `${label} rankedGarmentIds prefix: want ${JSON.stringify(wantRanked)}, got ${JSON.stringify(rankedIds)}`,
        );
      }
    }
  }

  const scores = expected.scores;
  if (scores && Object.keys(scores).length > 0) {
    const tol = expected.scoreTolerance ?? 0.0001;
    const byId = new Map(
      actual.alternatives.map((a) => [a.garmentId, a.score] as const),
    );
    for (const [id, want] of Object.entries(scores)) {
      const got = byId.get(id);
      if (got === undefined) {
        failures.push(`${label} score missing for ranked id: ${id}`);
        continue;
      }
      if (Math.abs(got - want) > tol) {
        failures.push(
          `${label} score ${id}: want ${want} (±${tol}), got ${got}`,
        );
      }
    }
  }
}

/**
 * A-STALE / D-33: post-swap ranking order must differ from pre-swap
 * (JSON.stringify compare per scenario doc).
 */
export function assertOrderDiffers(
  label: string,
  pre: string[],
  post: string[],
  failures: string[],
): boolean {
  const differs = JSON.stringify(pre) !== JSON.stringify(post);
  if (!differs) {
    failures.push(
      `${label} A-STALE: post-swap ranking identical to pre-swap (D-33)`,
    );
  }
  return differs;
}

export function alternativesFingerprint(
  step1: AlternativesResponse,
  step2: AlternativesResponse,
): string {
  const pack = (r: AlternativesResponse) => ({
    slot: r.slot,
    emptyReason: r.emptyReason ?? null,
    alternatives: r.alternatives.map((a) => ({
      garmentId: a.garmentId,
      score: a.score,
      setPartnerIds: a.setPartnerIds ?? null,
    })),
  });
  return JSON.stringify({ step1: pack(step1), step2: pack(step2) });
}
