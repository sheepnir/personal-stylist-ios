import { gapReasonFor } from "../stage3/rationaleTemplate.js";
import type {
  ContextSnapshot,
  GarmentSummary,
  OutfitAssignment,
  Slot,
  TemperatureBand,
} from "../types.js";
import { GAP_REASON_MAX_LENGTH, NOUL_ACCESSORY_THRESHOLD } from "./constants.js";
import {
  optionKeyIsOffered,
  resolveGarmentIdFromToken,
  resolveSetToken,
} from "./validateProviderMaps.js";
import { ownHas } from "./safeOwn.js";
import type {
  DecisionsAnswer,
  ProviderQuestion,
  ProviderSetToken,
} from "./types.js";

function truncateGapReason(text: string): string {
  if (text.length <= GAP_REASON_MAX_LENGTH) return text;
  return text.slice(0, GAP_REASON_MAX_LENGTH - 1) + "…";
}

function slotAllowsNone(question: ProviderQuestion): boolean {
  return (
    question.type === "choice" && optionKeyIsOffered(question.options, "none")
  );
}

function wardrobeById(
  wardrobe: GarmentSummary[],
): Map<string, GarmentSummary> {
  return new Map(wardrobe.map((g) => [g.id, g]));
}

export interface MapDecisionsResult {
  assignments: OutfitAssignment[];
  /** Tokens referenced that are not in tokenToGarmentId (before set expansion). */
  unknownTokens: string[];
}

export function mapDecisionsToAssignments(params: {
  questions: ProviderQuestion[];
  answers: Record<string, DecisionsAnswer>;
  tokenToGarmentId: Record<string, string>;
  setTokens?: ProviderSetToken[];
  seedAssignments: OutfitAssignment[];
  wardrobe: GarmentSummary[];
  context: ContextSnapshot;
  requiredSlots: Set<Slot>;
}): MapDecisionsResult {
  const {
    questions,
    answers,
    tokenToGarmentId,
    setTokens = [],
    seedAssignments,
    wardrobe,
    context,
    requiredSlots,
  } = params;

  const unknownTokens: string[] = [];
  const ignoredQuestionIds = new Set<string>();
  const byWardrobe = wardrobeById(wardrobe);

  const assignmentBySlot = new Map<Slot, OutfitAssignment>();
  const accessoryAssignments: OutfitAssignment[] = [];

  for (const a of seedAssignments) {
    if (a.slot === "ACCESSORY") {
      accessoryAssignments.push({ ...a });
    } else {
      assignmentBySlot.set(a.slot, { ...a });
    }
  }

  const band: TemperatureBand = context.temperatureBand;

  for (const question of questions) {
    if (ignoredQuestionIds.has(question.id)) continue;
    if (!ownHas(answers, question.id)) continue;
    const answer = answers[question.id];
    if (!answer) continue;

    if (question.type === "noul") {
      if (answer.type !== "noul") continue;
      if (answer.noul < NOUL_ACCESSORY_THRESHOLD) continue;
      const token = question.garmentToken;
      const garmentId = resolveGarmentIdFromToken(tokenToGarmentId, token);
      if (!garmentId) {
        unknownTokens.push(token);
        continue;
      }
      const g = byWardrobe.get(garmentId);
      if (!g) continue;
      accessoryAssignments.push({
        slot: "ACCESSORY",
        garmentId,
        isAnchor: false,
        isLocked: false,
        gapReason: null,
      });
      continue;
    }

    if (answer.type !== "choice") continue;
    const slot = question.slot;
    const choice = answer.choice;

    if (choice === "none") {
      if (!slotAllowsNone(question)) {
        assignmentBySlot.set(slot, {
          slot,
          garmentId: null,
          isAnchor: false,
          isLocked: false,
          gapReason: truncateGapReason(
            gapReasonFor(slot, "availability", band),
          ),
        });
      }
      continue;
    }

    if (choice.startsWith("s_")) {
      const setInfo = resolveSetToken(setTokens, choice);
      if (!setInfo) {
        unknownTokens.push(choice);
        continue;
      }
      for (let i = 0; i < setInfo.memberGarmentIds.length; i++) {
        const garmentId = setInfo.memberGarmentIds[i]!;
        const memberSlot = setInfo.memberSlots[i]!;
        assignmentBySlot.set(memberSlot, {
          slot: memberSlot,
          garmentId,
          isAnchor: false,
          isLocked: false,
          gapReason: null,
        });
      }
      for (const q of questions) {
        if (q.type !== "choice") continue;
        if (setInfo.memberSlots.includes(q.slot) && q.id !== question.id) {
          ignoredQuestionIds.add(q.id);
        }
      }
      continue;
    }

    const garmentId = resolveGarmentIdFromToken(tokenToGarmentId, choice);
    if (!garmentId) {
      unknownTokens.push(choice);
      continue;
    }
    assignmentBySlot.set(slot, {
      slot,
      garmentId,
      isAnchor: false,
      isLocked: false,
      gapReason: null,
    });
  }

  for (const slot of requiredSlots) {
    if (assignmentBySlot.has(slot)) continue;
    const existing = seedAssignments.find((a) => a.slot === slot && a.garmentId);
    if (existing) continue;
    assignmentBySlot.set(slot, {
      slot,
      garmentId: null,
      isAnchor: false,
      isLocked: false,
      gapReason: truncateGapReason(gapReasonFor(slot, "availability", band)),
    });
  }

  const assignments = [
    ...assignmentBySlot.values(),
    ...accessoryAssignments,
  ];

  return { assignments, unknownTokens };
}
