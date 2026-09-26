import { resolveRequiredSlots } from "../stage3/layers.js";
import { runStage4 } from "../stage4/runStage4.js";
import type { Slot } from "../types.js";
import {
  assignmentsGapReasonValid,
  composeProviderRationale,
  rationaleWithinLimits,
} from "./composeProviderRationale.js";
import { matchesExcludedGarmentSet } from "./excludeGarmentSets.js";
import { mapDecisionsToAssignments } from "./mapDecisionsToAssignments.js";
import { modelSlugMatches } from "./modelSlug.js";
import {
  parseDecisionsResponseBody,
  validateDecisionsAnswersAgainstQuestions,
} from "./parseDecisionsOutput.js";
import type {
  ValidateProviderOutputInput,
  ValidateProviderOutputResult,
} from "./types.js";

function filledOutfitMap(
  seedAssignments: ValidateProviderOutputInput["seedAssignments"],
): Map<Slot, string> {
  const filled = new Map<Slot, string>();
  for (const a of seedAssignments) {
    if (a.garmentId) filled.set(a.slot, a.garmentId);
  }
  return filled;
}

/**
 * ADR §6 / §7.1.3: validate Decisions-shaped provider output, map to assignments,
 * run runStage4 unchanged, then provider-only checks and server-side rationale.
 */
export function validateProviderOutput(
  input: ValidateProviderOutputInput,
): ValidateProviderOutputResult {
  const parsed = parseDecisionsResponseBody(input.responseBody);
  if (!parsed) {
    return { ok: false, cause: "OUTPUT_PARSE" };
  }

  if (!modelSlugMatches(parsed.model, input.expectedModelSlug)) {
    return { ok: false, cause: "OUTPUT_MODEL_MISMATCH" };
  }

  if (
    !validateDecisionsAnswersAgainstQuestions(
      parsed.answers,
      input.questions,
    )
  ) {
    return { ok: false, cause: "OUTPUT_SCHEMA" };
  }

  const filledSeed = filledOutfitMap(input.seedAssignments);
  const requiredSlots = resolveRequiredSlots(
    input.stage4.context,
    filledSeed,
    input.stage4.options,
  );

  const mapped = mapDecisionsToAssignments({
    questions: input.questions,
    answers: parsed.answers,
    tokenToGarmentId: input.tokenToGarmentId,
    setTokens: input.setTokens,
    seedAssignments: input.seedAssignments,
    wardrobe: input.stage4.wardrobe,
    context: input.stage4.context,
    requiredSlots,
  });

  if (mapped.unknownTokens.length > 0) {
    return { ok: false, cause: "OUTPUT_TOKEN_MAP" };
  }

  if (!assignmentsGapReasonValid(mapped.assignments)) {
    return { ok: false, cause: "OUTPUT_GAP_REASON" };
  }

  const stage4 = runStage4({
    ...input.stage4,
    assignments: mapped.assignments,
    fallbackLevel: "NONE",
  });

  if (!stage4.ok) {
    return {
      ok: false,
      cause: "OUTPUT_STAGE4",
      stage4ViolationCodes: stage4.violations.map((v) => v.code),
    };
  }

  if (
    matchesExcludedGarmentSet(
      mapped.assignments,
      input.excludeGarmentSets,
    )
  ) {
    return { ok: false, cause: "OUTPUT_EXCLUDED_SET" };
  }

  const rationale = composeProviderRationale(
    mapped.assignments,
    input.stage2,
    input.builderInput,
    input.stage4.wardrobe,
    stage4.cautions,
  );

  if (!rationaleWithinLimits(rationale)) {
    return { ok: false, cause: "OUTPUT_LENGTH" };
  }

  return {
    ok: true,
    assignments: mapped.assignments,
    rationale,
    stage4Cautions: stage4.cautions,
    usage: parsed.usage,
    model: parsed.model,
  };
}
