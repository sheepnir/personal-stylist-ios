import { activeCombinationRules } from "../stage3/combination.js";
import { templateRationale } from "../stage3/rationaleTemplate.js";
import type {
  BuilderInput,
  GarmentSummary,
  OutfitAssignment,
  Slot,
  Stage2Result,
  Stage4Caution,
} from "../types.js";
import { PROVIDER_PATH_RATIONALE_SUMMARY, RATIONALE_LIMITS } from "./constants.js";
import type { ProviderRationale } from "./types.js";

function outfitMapFromAssignments(
  assignments: OutfitAssignment[],
): Map<Slot, string> {
  const outfit = new Map<Slot, string>();
  for (const a of assignments) {
    if (!a.garmentId) continue;
    if (a.slot === "ACCESSORY") {
      const prev = outfit.get("ACCESSORY");
      const joined = prev
        ? [...prev.split(","), a.garmentId].sort().join(",")
        : a.garmentId;
      outfit.set("ACCESSORY", joined);
    } else {
      outfit.set(a.slot, a.garmentId);
    }
  }
  return outfit;
}

function mergeCautionsLikeGenerateLocal(
  templateCautions: string[] | undefined,
  stage4Cautions: Stage4Caution[],
): string[] | undefined {
  const builderCautions = [...(templateCautions ?? [])];
  const hasLockedDislikedPair = builderCautions.some((c) =>
    c.includes("Locked pieces include"),
  );

  const stage4Reasons: string[] = [];
  for (const s4c of stage4Cautions) {
    if (s4c.code === "LOCKED_DISLIKED_PAIR" && hasLockedDislikedPair) {
      continue;
    }
    stage4Reasons.push(s4c.reason);
  }

  let merged = [...stage4Reasons, ...builderCautions];
  if (merged.length > 2) merged = merged.slice(0, 2);
  return merged.length ? merged : undefined;
}

export function composeProviderRationale(
  assignments: OutfitAssignment[],
  stage2: Stage2Result,
  builderInput: BuilderInput,
  wardrobe: GarmentSummary[],
  stage4Cautions: Stage4Caution[],
): ProviderRationale {
  const wardrobeById = new Map(wardrobe.map((g) => [g.id, g]));
  const rules = activeCombinationRules(
    builderInput.profile?.activeRules,
    builderInput.context.occasion,
  );
  const outfit = outfitMapFromAssignments(assignments);
  const singleSlotOutfit = new Map<Slot, string>();
  for (const [slot, id] of outfit) {
    if (slot === "ACCESSORY" && id.includes(",")) {
      singleSlotOutfit.set(slot, id.split(",")[0]!);
    } else {
      singleSlotOutfit.set(slot, id);
    }
  }

  const templated = templateRationale(
    singleSlotOutfit,
    stage2,
    builderInput,
    wardrobeById,
    rules,
  );

  const cautions = mergeCautionsLikeGenerateLocal(
    templated.cautions,
    stage4Cautions,
  );

  return {
    summary: PROVIDER_PATH_RATIONALE_SUMMARY,
    pairingNotes: templated.pairingNotes,
    teachingNote: null,
    cautions,
  };
}

export function rationaleWithinLimits(rationale: ProviderRationale): boolean {
  if (rationale.summary.length > RATIONALE_LIMITS.summary) return false;
  if (
    rationale.pairingNotes?.some((n) => n.length > RATIONALE_LIMITS.pairingNote)
  ) {
    return false;
  }
  if (
    rationale.teachingNote != null &&
    rationale.teachingNote.length > RATIONALE_LIMITS.teachingNote
  ) {
    return false;
  }
  if (rationale.cautions?.some((c) => c.length > RATIONALE_LIMITS.caution)) {
    return false;
  }
  return true;
}

export function assignmentsGapReasonValid(
  assignments: OutfitAssignment[],
): boolean {
  for (const a of assignments) {
    const hasGarment = a.garmentId != null && a.garmentId !== "";
    const hasGap = a.gapReason != null && a.gapReason !== "";
    if (hasGarment && hasGap) return false;
    if (!hasGarment && !hasGap) {
      // Optional empty slots are omitted entirely; required gaps must carry gapReason.
      continue;
    }
  }
  return true;
}
