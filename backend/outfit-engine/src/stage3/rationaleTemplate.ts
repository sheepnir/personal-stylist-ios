import type {
  BuilderInput,
  GarmentSummary,
  OutfitAssignment,
  PreferenceRule,
  Relaxation,
  Slot,
  Stage2Result,
} from "../types.js";
import { WARMTH_TOLERANCE } from "../types.js";
import { lockedDislikedPairsPresent } from "./combination.js";

const SUMMARY =
  "Built this from your wardrobe without the stylist model — here's a solid pairing.";

function trunc(s: string, max: number): string {
  if (s.length <= max) return s;
  return s.slice(0, max - 1) + "…";
}

export function gapReasonFor(
  slot: Slot,
  cause: "availability" | "combination" | "layer",
  band?: string,
): string {
  let msg: string;
  switch (cause) {
    case "availability":
      msg = `No AVAILABLE ready ${slot}; availability is never relaxed.`;
      break;
    case "combination":
      msg = `No candidate for ${slot} compatible with locked/chosen pieces.`;
      break;
    case "layer":
      msg = `No ${slot} available for ${band ?? "band"} layer requirement.`;
      break;
    default:
      msg = `No candidate for ${slot}.`;
  }
  return trunc(msg, 120);
}

export function templateRationale(
  outfit: Map<Slot, string>,
  stage2: Stage2Result,
  input: BuilderInput,
  wardrobeById: Map<string, GarmentSummary>,
  comboRules: PreferenceRule[],
): {
  summary: string;
  pairingNotes?: string[];
  teachingNote?: string | null;
  cautions?: string[];
} {
  const pairingNotes: string[] = [];
  const cautions: string[] = [];

  const fixedAnchor = stage2.fixed.find((f) => f.role === "anchor");
  if (fixedAnchor) {
    const g = wardrobeById.get(fixedAnchor.garmentId);
    if (g) {
      pairingNotes.push(`Anchored on ${g.displayName}.`);
    }
  }

  for (const [slot, id] of outfit) {
    if (fixedAnchor && id === fixedAnchor.garmentId) continue;
    if (stage2.fixed.some((f) => f.garmentId === id)) continue;
    const g = wardrobeById.get(id);
    if (!g) continue;
    const family = g.colorPrimary?.family;
    pairingNotes.push(
      family
        ? `Paired ${slot.toLowerCase()} ${g.displayName} (${family}).`
        : `Paired ${slot.toLowerCase()} ${g.displayName}.`,
    );
    if (pairingNotes.length >= 3) break;
  }

  for (const r of stage2.relaxationsApplied) {
    if (r.step === "WARMTH_WIDENED") {
      cautions.push(
        trunc(
          `Warmth window widened for ${r.slot}${r.note ? `: ${r.note}` : ""}.`,
          120,
        ),
      );
    }
    if (r.step === "FORMALITY_WIDENED") {
      cautions.push(
        trunc(
          `Formality window widened for ${r.slot}${r.note ? `: ${r.note}` : ""}.`,
          120,
        ),
      );
    }
  }

  const outfitIds = new Set(outfit.values());
  for (const hit of lockedDislikedPairsPresent(outfitIds, comboRules)) {
    cautions.push(
      trunc(
        `Locked pieces include a disliked combination (${hit.id ?? "rule"}); kept per your locks.`,
        120,
      ),
    );
  }

  const occasionF = input.context.occasionFormality;
  if (fixedAnchor) {
    const ag = wardrobeById.get(fixedAnchor.garmentId);
    if (
      ag?.formality != null &&
      occasionF != null &&
      ag.formality < occasionF - 1
    ) {
      cautions.push(
        trunc(
          `${ag.displayName} is the casual element against a more formal occasion.`,
          120,
        ),
      );
    }
  }

  const [warmLo, warmHi] = WARMTH_TOLERANCE[input.context.temperatureBand];
  for (const [, id] of outfit) {
    const g = wardrobeById.get(id);
    if (!g) continue;
    if (g.warmth != null && (g.warmth < warmLo || g.warmth > warmHi)) {
      cautions.push(
        trunc(
          `${g.displayName} sits outside the ${input.context.temperatureBand} warmth window.`,
          120,
        ),
      );
    }
    const conf = g.attributeConfidence;
    if (conf && typeof conf === "object") {
      const lowFields = Object.entries(conf)
        .filter(([, v]) => typeof v === "number" && v < 0.6)
        .map(([k]) => k);
      if (lowFields.length > 0) {
        cautions.push(
          trunc(
            `${g.displayName} has low-confidence attributes (${lowFields.join(", ")}).`,
            120,
          ),
        );
      }
    }
  }

  return {
    summary: trunc(SUMMARY, 200),
    pairingNotes: pairingNotes.slice(0, 3),
    teachingNote: null,
    cautions: cautions.length ? cautions : undefined,
  };
}

export function passthroughRelaxations(stage2: Stage2Result): Relaxation[] {
  return stage2.relaxationsApplied.map((r) => ({ ...r }));
}
