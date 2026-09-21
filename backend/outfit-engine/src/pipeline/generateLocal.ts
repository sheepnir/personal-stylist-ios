/**
 * Local deterministic generate bridge — Stage1 → Stage2 → Builder → Stage4.
 * Zero network / zero OpenRouter. Maps to OpenAPI-ish GenerateResponse / Problem.
 */

import { runStage1 } from "../stage1/hardFilter.js";
import { runStage2 } from "../stage2/runStage2.js";
import { runBuilder } from "../stage3/runBuilder.js";
import { runStage4 } from "../stage4/runStage4.js";
import type {
  Boldness,
  BuilderResult,
  ContextSnapshot,
  GarmentSet,
  GarmentSummary,
  OutfitAssignment,
  Slot,
  Stage1Conflict,
  Stage1Input,
  Stage1Options,
  Stage1Problem,
  Stage2Input,
  Stage4Caution,
  StyleProfilePayload,
} from "../types.js";

/** GenerateRequest-ish + local aliases (anchor / locks / sets). */
export interface LocalGenerateRequest {
  wardrobe: GarmentSummary[];
  context: ContextSnapshot;
  profile?: StyleProfilePayload | null;
  /** OpenAPI name */
  anchorGarmentId?: string | null;
  /** Alias for anchorGarmentId */
  anchor?: string | null;
  lockedAssignments?: OutfitAssignment[];
  /** Alias for lockedAssignments */
  locks?: OutfitAssignment[];
  options?: Stage1Options & {
    candidatesPerSlot?: number;
    accessoryPolicy?: "OPEN" | "LOCKED";
    requireSlots?: Slot[];
    excludeGarmentSets?: string[][];
  };
  sets?: GarmentSet[];
  boldness?: Boldness;
  /** Optional history-ish inputs ignored by deterministic path except asOfDate */
  asOfDate?: string;
  requestId?: string | null;
  recentOutfits?: string[][];
}

export interface LocalProblemBody {
  title: string;
  status: 400;
  detail: string;
  code: string;
  conflicts?: Stage1Conflict[];
  /** Stage 4 validation failures (M0-19). */
  violations?: import("../types.js").Stage4Violation[];
  dataPreserved: true;
  type?: string;
}

export interface LocalGenerateResponse {
  outfitId: string;
  assignments: OutfitAssignment[];
  rationale: BuilderResult["rationale"];
  boldnessUsed: BuilderResult["boldnessUsed"];
  noAlternativeReason?: string | null;
  relaxationsApplied: BuilderResult["relaxationsApplied"];
  candidateSet?: BuilderResult["candidateSet"];
  generation: {
    modelId: string;
    promptVersion: "none" | string;
    candidateSetHash: string | null;
    latencyMs: number;
    inputTokens: null;
    outputTokens: null;
    costUSD: 0;
    repairAttempts: 0;
    fallbackLevel: "DETERMINISTIC";
    spendState: "OK" | "SOFT_THRESHOLD" | "HARD_CAP_DETERMINISTIC";
  };
}

export type GenerateLocalOutput = LocalGenerateResponse | LocalProblemBody;

export function isLocalProblem(
  result: GenerateLocalOutput,
): result is LocalProblemBody {
  return (
    typeof result === "object" &&
    result !== null &&
    "status" in result &&
    (result as LocalProblemBody).status === 400 &&
    "code" in result
  );
}

function toStage1Input(request: LocalGenerateRequest): Stage1Input {
  return {
    wardrobe: request.wardrobe,
    context: request.context,
    anchorGarmentId:
      request.anchorGarmentId ?? request.anchor ?? null,
    lockedAssignments:
      request.lockedAssignments ?? request.locks ?? [],
    options: request.options
      ? {
          requireSlots: request.options.requireSlots,
          accessoryPolicy: request.options.accessoryPolicy,
          candidatesPerSlot: request.options.candidatesPerSlot,
        }
      : undefined,
    profile: request.profile ?? null,
    sets: request.sets,
  };
}

function toStage2Input(request: LocalGenerateRequest): Stage2Input {
  const asOfDate =
    request.asOfDate ?? request.context.capturedAt ?? undefined;
  
  const history =
    request.recentOutfits && request.recentOutfits.length > 0
      ? {
          suggestions: request.recentOutfits.map((garmentIds) => ({
            suggestedAt: asOfDate || new Date().toISOString(),
            garmentIds,
          })),
        }
      : null;

  return {
    wardrobe: request.wardrobe,
    context: request.context,
    profile: request.profile ?? null,
    boldness: request.boldness,
    sets: request.sets,
    options: request.options
      ? {
          requireSlots: request.options.requireSlots,
          accessoryPolicy: request.options.accessoryPolicy,
          candidatesPerSlot: request.options.candidatesPerSlot,
          excludeGarmentSets: request.options.excludeGarmentSets,
        }
      : undefined,
    asOfDate,
    history,
  };
}

/**
 * OpenAPI Problem conflicts shape: garmentId + reason (extras like role/slot OK).
 * Ensures every entry has a human reason before any model / Stage2 call.
 */
function mapConflicts(
  conflicts: Stage1Conflict[] | undefined,
): Stage1Conflict[] | undefined {
  if (!conflicts?.length) return conflicts;
  return conflicts.map((c) => ({
    ...c,
    garmentId: c.garmentId,
    reason:
      c.reason?.trim() ||
      (c.role
        ? `Conflict involving ${c.garmentId} (${c.role})`
        : `Conflict involving ${c.garmentId}`),
  }));
}

function mapProblem(problem: Stage1Problem): LocalProblemBody {
  const conflicts = mapConflicts(problem.conflicts);
  return {
    type: "about:blank",
    title: problem.title,
    status: 400,
    detail: problem.detail,
    code: problem.code,
    ...(conflicts ? { conflicts } : {}),
    dataPreserved: true,
  };
}

function mapBuilderResult(
  builder: BuilderResult,
  stage4Cautions?: Stage4Caution[],
): LocalGenerateResponse {
  // Merge Stage 4 cautions into rationale.cautions, honoring OpenAPI maxItems: 2.
  // Prefer Stage4 (esp. LAYER_REQUIREMENT) before builder relaxations so
  // truncation does not drop layer warnings (#122 / #35 AC2).
  const builderCautions = [...(builder.rationale.cautions ?? [])];

  // Check if builder already reported LOCKED_DISLIKED_PAIR to avoid duplicate
  const hasLockedDislikedPair = builderCautions.some((c) =>
    c.includes("Locked pieces include"),
  );

  const stage4Reasons: string[] = [];
  if (stage4Cautions?.length) {
    for (const s4c of stage4Cautions) {
      if (s4c.code === "LOCKED_DISLIKED_PAIR" && hasLockedDislikedPair) {
        continue;
      }
      stage4Reasons.push(s4c.reason);
    }
  }

  let mergedCautions = [...stage4Reasons, ...builderCautions];
  if (mergedCautions.length > 2) {
    mergedCautions = mergedCautions.slice(0, 2);
  }

  return {
    outfitId: builder.outfitId,
    assignments: builder.assignments,
    rationale: {
      ...builder.rationale,
      cautions: mergedCautions.length ? mergedCautions : undefined,
    },
    boldnessUsed: builder.boldnessUsed,
    noAlternativeReason: builder.noAlternativeReason ?? null,
    relaxationsApplied: builder.relaxationsApplied,
    candidateSet: builder.candidateSet,
    generation: {
      modelId: builder.generation.modelId,
      promptVersion: builder.generation.promptVersion,
      candidateSetHash: builder.generation.candidateSetHash,
      latencyMs: builder.generation.latencyMs,
      inputTokens: null,
      outputTokens: null,
      costUSD: 0,
      repairAttempts: 0,
      fallbackLevel: "DETERMINISTIC",
      spendState: builder.generation.spendState ?? "OK",
    },
  };
}

/**
 * Run the full deterministic pipeline for a generate-shaped request.
 * Stage1 Problem → 400-shaped body (no Stage2/Builder).
 * Otherwise Stage2 → Builder → Stage4 → OpenAPI-ish GenerateResponse
 * (or VALIDATION_FAILED Problem if Stage 4 rejects).
 */
export function generateLocal(
  request: LocalGenerateRequest,
): GenerateLocalOutput {
  if (!request?.wardrobe || !request?.context) {
    return {
      type: "about:blank",
      title: "Invalid request",
      status: 400,
      detail: "Request must include wardrobe and context.",
      code: "INVALID_REQUEST",
      dataPreserved: true,
    };
  }

  const stage1Input = toStage1Input(request);
  const stage1 = runStage1(stage1Input);

  if (!stage1.ok) {
    return mapProblem(stage1 as Stage1Problem);
  }

  const stage2Input = toStage2Input(request);
  const stage2 = runStage2(stage1, stage2Input);
  const builder = runBuilder(stage2, stage2Input);

  const stage4 = runStage4({
    assignments: builder.assignments,
    candidateIds: stage2.candidateIds,
    candidateSet: builder.candidateSet,
    fixed: stage2.fixed,
    wardrobe: request.wardrobe,
    context: request.context,
    profile: request.profile ?? null,
    sets: request.sets,
    options: {
      requireSlots: request.options?.requireSlots,
      accessoryPolicy: request.options?.accessoryPolicy,
    },
    rationale: builder.rationale,
    fallbackLevel: "DETERMINISTIC",
  });

  if (!stage4.ok) {
    const detail =
      ("violations" in stage4 ? stage4.violations : [])
        .map((v) => v.reason)
        .join("; ") || "Outfit failed Stage 4 validation";
    return {
      type: "about:blank",
      title: "Outfit validation failed",
      status: 400,
      detail,
      code: "VALIDATION_FAILED",
      violations: "violations" in stage4 ? stage4.violations : [],
      dataPreserved: true,
    };
  }

  return mapBuilderResult(builder, stage4.cautions);
}
