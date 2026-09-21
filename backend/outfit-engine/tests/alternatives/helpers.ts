import type {
  ContextSnapshot,
  GarmentSummary,
  OutfitAssignment,
  Slot,
  StyleProfilePayload,
} from "../../src/types.js";
import {
  loadScenario,
  loadSets,
  stage1InputFromScenario,
} from "../stage1/helpers.js";
import { generateLocal, isLocalProblem } from "../../src/pipeline/generateLocal.js";
import type { AlternativesRequest } from "../../src/alternatives/rankAlternatives.js";

export {
  loadGarments,
  loadSets,
  loadScenario,
  stage1InputFromScenario,
  mildWorkContext,
} from "../stage1/helpers.js";

export function mildContext(
  formality = 3,
  band: ContextSnapshot["temperatureBand"] = "MILD",
): ContextSnapshot {
  return {
    occasion: "WORK_STANDARD",
    occasionFormality: formality,
    temperatureBand: band,
    precipitation: false,
    capturedAt: "2026-09-18T09:00:00-07:00",
  };
}

export function baseGarment(
  partial: Partial<GarmentSummary> &
    Pick<GarmentSummary, "id" | "displayName" | "slot">,
): GarmentSummary {
  return {
    category: "generic",
    colorPrimary: { family: "navy", hex: "#1b3a6b", name: "Navy" },
    colorSecondary: null,
    pattern: "SOLID",
    materials: ["cotton"],
    surface: "SMOOTH",
    formality: 3,
    warmth: 2,
    seasons: ["SPRING", "SUMMER", "FALL", "WINTER"],
    fit: "REGULAR",
    lastWornOn: null,
    daysSinceIntake: 30,
    isFavorite: false,
    wantToWearMore: false,
    comfortIssue: false,
    setId: null,
    keepTogether: false,
    availability: "AVAILABLE",
    readiness: "READY",
    owned: true,
    ...partial,
  };
}

export function assignment(
  slot: Slot,
  garmentId: string | null,
  opts: { isAnchor?: boolean; isLocked?: boolean; gapReason?: string | null } = {},
): OutfitAssignment {
  return {
    slot,
    garmentId,
    isAnchor: opts.isAnchor ?? false,
    isLocked: opts.isLocked ?? false,
    gapReason: opts.gapReason ?? null,
  };
}

/** Build a minimal happy-path outfit from T2-01 generate. */
export function generatedT201Outfit(): {
  wardrobe: GarmentSummary[];
  context: ContextSnapshot;
  profile: StyleProfilePayload | null | undefined;
  sets: ReturnType<typeof loadSets>;
  assignments: OutfitAssignment[];
  candidateSet: Record<string, unknown> | undefined;
} {
  const scenario = loadScenario("T2-01-sportcoat-mild-work");
  const s1 = stage1InputFromScenario(scenario);
  const gen = generateLocal({
    wardrobe: s1.wardrobe,
    context: s1.context,
    anchorGarmentId: s1.anchorGarmentId,
    lockedAssignments: s1.lockedAssignments,
    options: s1.options,
    profile: s1.profile,
    sets: s1.sets,
  });
  if (isLocalProblem(gen)) {
    throw new Error(`T2-01 generate failed: ${gen.code} ${gen.detail}`);
  }
  return {
    wardrobe: s1.wardrobe,
    context: s1.context,
    profile: s1.profile,
    sets: s1.sets ?? loadSets(),
    assignments: gen.assignments,
    candidateSet: gen.candidateSet as Record<string, unknown> | undefined,
  };
}

export function altReq(
  partial: Partial<AlternativesRequest> &
    Pick<AlternativesRequest, "slot" | "currentAssignments" | "wardrobe" | "context">,
): AlternativesRequest {
  return {
    profile: partial.profile ?? { version: 1, activeRules: [] },
    limit: 8,
    ...partial,
  };
}
