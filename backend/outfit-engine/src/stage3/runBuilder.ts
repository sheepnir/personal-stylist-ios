import { createHash } from "node:crypto";
import { resolveScoringConfig } from "../stage2/config.js";
import type {
  BuilderConfig,
  BuilderInput,
  BuilderPlacedMeta,
  BuilderResult,
  OutfitAssignment,
  Slot,
  Stage2Result,
  ScoredCandidate,
} from "../types.js";
import { activeCombinationRules, completesForbiddenPair } from "./combination.js";
import { resolveBuilderConfig } from "./config.js";
import {
  resolveCoolLayerSlot,
  resolveRequiredSlots,
  shouldFillOptional,
} from "./layers.js";
import { sortAssignmentsInline } from "./order.js";
import {
  buildPlaceContext,
  tryPlace,
  tryPlaceAccessories,
  type OutfitMap,
} from "./place.js";
import {
  gapReasonFor,
  passthroughRelaxations,
  templateRationale,
} from "./rationaleTemplate.js";

function assertStage2Ok(stage2: Stage2Result): void {
  if (!stage2 || stage2.ok !== true) {
    throw new Error("runBuilder requires stage2.ok === true");
  }
}

/**
 * Resolve asOfDate to a local calendar date (YYYY-MM-DD).
 * Falls back to context.capturedAt or wall clock if not provided.
 */
function resolveAsOfDate(input: BuilderInput): string {
  let dateStr: string;
  
  if (input.asOfDate) {
    dateStr = input.asOfDate;
  } else if (input.context.capturedAt) {
    dateStr = input.context.capturedAt;
  } else {
    dateStr = new Date().toISOString();
  }
  
  const datePart = dateStr.includes("T") ? dateStr.split("T")[0] : dateStr;
  return datePart;
}


function seedFixed(stage2: Stage2Result): {
  outfit: OutfitMap;
  assignments: OutfitAssignment[];
  placed: BuilderPlacedMeta[];
  fixedAccessoryIds: string[];
} {
  const outfit: OutfitMap = new Map();
  const assignments: OutfitAssignment[] = [];
  const placed: BuilderPlacedMeta[] = [];
  const fixedAccessoryIds: string[] = [];
  for (const f of stage2.fixed) {
    // D-32 #30-1: ACCESSORY is multi-valued; don't overwrite in Map<Slot,string>
    if (f.slot !== "ACCESSORY") {
      outfit.set(f.slot, f.garmentId);
    } else {
      fixedAccessoryIds.push(f.garmentId);
    }
    assignments.push({
      slot: f.slot,
      garmentId: f.garmentId,
      isAnchor: f.role === "anchor",
      isLocked: f.role === "lock",
      gapReason: null,
    });
    placed.push({
      slot: f.slot,
      garmentId: f.garmentId,
      source: "fixed",
    });
  }
  return { outfit, assignments, placed, fixedAccessoryIds };
}

function canonicalOutfitId(
  fixed: Stage2Result["fixed"],
  chosen: Map<Slot, string>,
  gaps: Slot[],
  weightsVersion: string,
): string {
  const fixedPart = [...fixed]
    .map((f) => `${f.slot}:${f.garmentId}:${f.role}`)
    .sort()
    .join("|");
  const chosenPart = [...chosen.entries()]
    .map(([s, id]) => `${s}:${id}`)
    .sort()
    .join("|");
  const gapsPart = [...gaps].sort().join(",");
  const payload = `v1|${weightsVersion}|${fixedPart}|${chosenPart}|${gapsPart}`;
  const digest = createHash("sha256").update(payload).digest();
  const bytes = Buffer.from(digest.subarray(0, 16));
  bytes[6] = (bytes[6]! & 0x0f) | 0x50; // version 5
  bytes[8] = (bytes[8]! & 0x3f) | 0x80; // RFC 4122 variant
  const hex = bytes.toString("hex");
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20, 32)}`;
}

function hashCandidateIds(
  candidateIds: Stage2Result["candidateIds"],
): string {
  const parts: string[] = [];
  for (const slot of Object.keys(candidateIds).sort() as Slot[]) {
    const ids = candidateIds[slot] ?? [];
    parts.push(`${slot}:${ids.join(",")}`);
  }
  return createHash("sha256").update(parts.join("|")).digest("hex").slice(0, 32);
}

function gapCause(
  slot: Slot,
  stage2: Stage2Result,
  layerRequired: boolean,
): "availability" | "combination" | "layer" {
  if (layerRequired && (slot === "OUTERWEAR" || slot === "MID_LAYER" || slot === "JACKET")) {
    const list = stage2.shortlist[slot] ?? [];
    if (list.length === 0) return "layer";
  }
  if (stage2.gaps.includes(slot)) return "availability";
  const list = stage2.shortlist[slot] ?? [];
  if (list.length === 0) return "availability";
  return "combination";
}

/**
 * Deterministic §9.5 L3 outfit builder — pure, no network.
 */
export function runBuilder(
  stage2: Stage2Result,
  input: BuilderInput,
  config?: Partial<BuilderConfig> | null,
): BuilderResult {
  const t0 = Date.now();
  assertStage2Ok(stage2);
  const cfg = resolveBuilderConfig(config);

  const { outfit, assignments: seedAssignments, placed, fixedAccessoryIds } =
    seedFixed(stage2);
  const accessoryPlacedIds: string[] = [];

  const rules = activeCombinationRules(
    input.profile?.activeRules,
    input.context.occasion,
  );
  
  const required = resolveRequiredSlots(
    input.context,
    outfit,
    input.options,
  );
  
  // D-41: Build rescore context for dynamic re-scoring
  const asOfDate = resolveAsOfDate(input);
  const scoringConfig = resolveScoringConfig(null);
  const rescoreContext = {
    context: input.context,
    history: input.history,
    asOfDate,
    config: scoringConfig,
  };
  
  const ctx = buildPlaceContext(
    stage2,
    input.wardrobe,
    input.sets,
    rules,
    outfit,
    rescoreContext,
  );
  
  // D-41: Track whether we should seed a pseudo-anchor for no-anchor requests
  const hasAnchor = stage2.fixed.some((f) => f.role === "anchor");
  let pseudoAnchorId: string | null = null;
  let firstRequiredSlotPlaced = false;
  
  // D-32 #30-1: Add fixed accessories to outfitIds (not in outfit Map)
  for (const id of fixedAccessoryIds) {
    ctx.outfitIds.add(id);
  }

  // COOL: require exactly one layer slot if none filled
  const band = input.context.temperatureBand;
  if (band === "COOL") {
    const hasLayer =
      outfit.has("MID_LAYER") ||
      outfit.has("JACKET") ||
      outfit.has("OUTERWEAR");
    if (!hasLayer) {
      const tops: Partial<
        Record<Slot, { garmentId: string; score: number } | null>
      > = {};
      for (const s of ["MID_LAYER", "JACKET", "OUTERWEAR"] as Slot[]) {
        const list = stage2.shortlist[s] ?? [];
        const first = list[0];
        tops[s] = first
          ? { garmentId: first.garmentId, score: first.score }
          : null;
      }
      required.add(resolveCoolLayerSlot(tops));
    }
  }

  const gapsOut = new Set<Slot>(stage2.gaps);

  const accessoryPolicy = input.options?.accessoryPolicy ?? "OPEN";

  for (const slot of cfg.fillOrder) {
    if (outfit.has(slot) && slot !== "ACCESSORY") continue;
    if (gapsOut.has(slot) && slot !== "ACCESSORY") {
      // Forced gap from Stage 2 — skip try
      continue;
    }

    const isRequired = required.has(slot);
    const optional = shouldFillOptional(
      slot,
      band,
      cfg,
      accessoryPolicy,
      input.context.precipitation,
    );
    if (!isRequired && !optional) continue;

    if (slot === "ACCESSORY") {
      if (!cfg.fillOptionalAccessories || accessoryPolicy === "LOCKED") {
        continue;
      }
      const acc = tryPlaceAccessories(ctx, cfg.maxAccessories);
      for (const p of acc) {
        accessoryPlacedIds.push(p.garmentId);
        placed.push(p);
      }
      continue;
    }

    const result = tryPlace(slot, ctx, pseudoAnchorId);
    if (result.placed) {
      for (const p of result.placements) {
        placed.push(p);
        // Partners may fill other slots — remove from gaps/required tracking
        gapsOut.delete(p.slot);
        required.delete(p.slot);
      }
      // D-41: After placing first required slot in no-anchor case, use it as pseudo-anchor
      if (!hasAnchor && !firstRequiredSlotPlaced && isRequired && result.placements.length > 0) {
        pseudoAnchorId = result.placements[0].garmentId;
        firstRequiredSlotPlaced = true;
      }
    } else if (isRequired || stage2.gaps.includes(slot)) {
      gapsOut.add(slot);
    }
  }

  // D-20 try-another: if the built id-set was already shown, backtrack the
  // lowest-priority free slot; if exhausted, keep the best + noAlternativeReason.
  const excludeSets = input.options?.excludeGarmentSets ?? [];
  let noAlternativeReason: string | null = null;
  const filledIdList = (): string[] =>
    [...outfit.values(), ...accessoryPlacedIds].sort();
  const sameIdSet = (a: string[], b: string[]): boolean => {
    if (a.length !== b.length) return false;
    const sa = [...a].sort();
    const sb = [...b].sort();
    return sa.every((id, i) => id === sb[i]);
  };
  const isExcludedSet = (ids: string[]): boolean =>
    excludeSets.some((ex) => sameIdSet(ex, ids));

  if (excludeSets.length > 0 && isExcludedSet(filledIdList())) {
    const freeSlots = cfg.fillOrder.filter(
      (s) =>
        s !== "ACCESSORY" &&
        outfit.has(s) &&
        !stage2.fixed.some((f) => f.slot === s),
    );
    let resolved = false;
    for (const slot of [...freeSlots].reverse()) {
      const current = outfit.get(slot);
      if (!current) continue;
      const others = [...outfit.entries()]
        .filter(([s]) => s !== slot)
        .map(([, id]) => ctx.wardrobeById.get(id))
        .filter((g): g is NonNullable<typeof g> => g != null);
      const otherIds = new Set(others.map((g) => g.id));
      for (const c of stage2.shortlist[slot] ?? []) {
        if (c.garmentId === current) continue;
        if (otherIds.has(c.garmentId)) continue;
        const g = ctx.wardrobeById.get(c.garmentId);
        if (!g) continue;
        if (completesForbiddenPair(g, otherIds, others, rules)) continue;
        outfit.set(slot, c.garmentId);
        ctx.outfitIds.delete(current);
        ctx.outfitIds.add(c.garmentId);
        if (!isExcludedSet(filledIdList())) {
          const idx = placed.findIndex(
            (p) => p.slot === slot && p.garmentId === current,
          );
          if (idx >= 0) {
            placed[idx] = {
              slot,
              garmentId: c.garmentId,
              source: "shortlist",
            };
          }
          resolved = true;
          break;
        }
        outfit.set(slot, current);
        ctx.outfitIds.delete(c.garmentId);
        ctx.outfitIds.add(current);
      }
      if (resolved) break;
    }
    if (!resolved) {
      noAlternativeReason =
        "No different combination remains for the unlocked slots.";
    }
  }

  // Build assignment list: seed + free picks + gaps
  const assignmentBySlot = new Map<Slot, OutfitAssignment>();
  const fixedAccessories: OutfitAssignment[] = [];
  for (const a of seedAssignments) {
    // D-32: ACCESSORY is multi-valued; collect separately so three locks stay intact.
    if (a.slot === "ACCESSORY") {
      fixedAccessories.push(a);
    } else {
      assignmentBySlot.set(a.slot, a);
    }
  }

  for (const p of placed) {
    if (p.source === "fixed") continue;
    if (p.slot === "ACCESSORY") continue;
    assignmentBySlot.set(p.slot, {
      slot: p.slot,
      garmentId: p.garmentId,
      isAnchor: false,
      isLocked: false,
      gapReason: null,
    });
  }

  for (const slot of gapsOut) {
    if (assignmentBySlot.has(slot) && assignmentBySlot.get(slot)?.garmentId) {
      continue;
    }
    const layerReq =
      (band === "COLD" && slot === "OUTERWEAR") ||
      (band === "COOL" &&
        (slot === "MID_LAYER" || slot === "JACKET" || slot === "OUTERWEAR"));
    const cause = gapCause(slot, stage2, layerReq);
    assignmentBySlot.set(slot, {
      slot,
      garmentId: null,
      isAnchor: false,
      isLocked: false,
      gapReason: gapReasonFor(slot, cause, band),
    });
  }

  const nonAccessory = [...assignmentBySlot.values()];
  const accessoryAssignments: OutfitAssignment[] = [
    ...fixedAccessories,
    ...accessoryPlacedIds.map((id) => ({
      slot: "ACCESSORY" as const,
      garmentId: id,
      isAnchor: false,
      isLocked: false,
      gapReason: null,
    })),
  ];

  const assignments = sortAssignmentsInline(
    [...nonAccessory, ...accessoryAssignments],
    cfg.fillOrder,
  );

  // Chosen map for outfitId (exclude gaps)
  const chosen = new Map<Slot, string>();
  for (const [s, id] of outfit) chosen.set(s, id);
  // Multi-accessory: fold into hash via sorted ids under ACCESSORY key
  if (accessoryPlacedIds.length) {
    chosen.set(
      "ACCESSORY",
      [...accessoryPlacedIds].sort().join(","),
    );
  }

  const gapsEmitted = [...gapsOut].sort();
  const outfitId = canonicalOutfitId(
    stage2.fixed,
    chosen,
    gapsEmitted,
    stage2.meta.weightsVersion,
  );

  const wardrobeById = ctx.wardrobeById;
  const rationale = templateRationale(
    outfit,
    stage2,
    input,
    wardrobeById,
    rules,
  );

  const candidateSet: BuilderResult["candidateSet"] = {};
  for (const [slot, list] of Object.entries(stage2.shortlist) as [
    Slot,
    NonNullable<Stage2Result["shortlist"][Slot]>,
  ][]) {
    candidateSet[slot] = list.map((c) => ({
      garmentId: c.garmentId,
      score: c.score,
      reason: c.overCapReason ?? null,
    }));
  }

  const latencyMs = Math.max(0, Date.now() - t0);

  return {
    ok: true,
    outfitId,
    assignments: sortAssignmentsInline(assignments, cfg.fillOrder),
    rationale,
    boldnessUsed: stage2.meta.boldness,
    noAlternativeReason,
    relaxationsApplied: passthroughRelaxations(stage2),
    candidateSet,
    generation: {
      modelId: cfg.builderModelId,
      promptVersion: "none",
      candidateSetHash: hashCandidateIds(stage2.candidateIds),
      latencyMs,
      inputTokens: null,
      outputTokens: null,
      costUSD: 0,
      repairAttempts: 0,
      fallbackLevel: "DETERMINISTIC",
      spendState: "OK",
    },
    builderMeta: {
      fillOrder: [...cfg.fillOrder],
      placed: [...placed],
      skipped: [...ctx.skipped],
      gapsEmitted,
      weightsVersion: stage2.meta.weightsVersion,
    },
  };
}
