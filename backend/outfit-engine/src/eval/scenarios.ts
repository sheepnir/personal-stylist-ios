/**
 * Load T2 / outfit scenario fixtures for the eval harness.
 */

import { existsSync, readdirSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import type { LocalGenerateRequest } from "../pipeline/generateLocal.js";
import type {
  Boldness,
  ContextSnapshot,
  GarmentSet,
  GarmentSummary,
  OutfitAssignment,
  StyleProfilePayload,
} from "../types.js";

const __dirname = dirname(fileURLToPath(import.meta.url));

/** Default: PersonalStylist/fixtures (four levels up from src/eval). */
export function defaultFixturesRoot(): string {
  return join(__dirname, "../../../../fixtures");
}

export interface ScenarioExpected {
  kind: string;
  /** When true, complete_outfit IDs are advisory not binding; for temporarily documenting engine gaps. */
  soft_ids?: boolean;
  complete_outfit?: Record<string, string>;
  complete_outfit_partial?: Record<string, string>;
  gap?: {
    slot?: string;
    reason?: string;
    problem_code?: string;
    conflicts?: unknown[];
  };
  no_outfit_produced?: boolean;
  refuse_partial_set?: boolean;
  must_include?: string[];
  must_exclude_garment_ids?: string[];
  must_exclude_slots?: string[];
  must_exclude_color_families?: string[];
  must_exclude_together?: string[];
  combination_rule?: {
    forbidden_pair?: string[];
    at_most_one_member_in_outfit?: boolean;
    neither_globally_absent?: boolean;
  };
  formality_range?: [number, number];
  set_atomicity?: {
    setId?: string;
    shortlist_over_cap?: boolean;
    required_together?: string[];
    any_result_using_either_uses_both?: boolean;
  };
  layer_requirement?: {
    temperatureBand?: string;
    requiredSlots?: string[];
  };
  [key: string]: unknown;
}

/** One step in a multi-step alternatives / swap-rerank fixture (M1-F05-07). */
export interface AlternativesScenarioStep {
  step: number;
  action: string;
  description?: string;
  request: {
    slot: string;
    currentAssignments: OutfitAssignment[];
    limit?: number;
  };
  expected: {
    httpStatus?: number;
    emptyReason?: string | null;
    rankedGarmentIds?: string[];
    rankedDisplayNames?: string[];
    scores?: Record<string, number>;
    scoreTolerance?: number;
    reasons?: Record<string, string>;
    setPartnerIds?: Record<string, string[] | null>;
    must_exclude_ids?: string[];
    must_exclude_notes?: Record<string, string>;
    apply_swap?: {
      slot: string;
      garmentId: string;
      setPartnerIds?: string[];
    };
    post_swap_assignments?: OutfitAssignment[];
    order_vs_pre_swap_top?: {
      pre_swap_rankedGarmentIds?: string[];
      pre_swap_note?: string;
      assert_order_differs?: boolean;
    };
    locks?: Record<string, unknown>;
    sets?: Record<string, unknown>;
    [key: string]: unknown;
  };
}

export interface ScenarioFile {
  id: string;
  title?: string;
  task?: string;
  /** Top-level kind for multi-step fixtures (e.g. alternatives_swap_rerank). */
  kind?: string;
  inputs: {
    wardrobe: GarmentSummary[];
    context: ContextSnapshot;
    anchorGarmentId?: string | null;
    lockedAssignments?: OutfitAssignment[];
    options?: LocalGenerateRequest["options"];
    profile?: StyleProfilePayload | null;
    sets?: GarmentSet[];
    boldness?: Boldness;
    startingAssignments?: OutfitAssignment[];
    fixture_overrides?: {
      availability?: Record<string, string>;
    };
    local_drafts?: string[];
  };
  /** Present for T2 generate scenarios. */
  expected?: ScenarioExpected;
  /** Multi-step alternatives fixtures (M1-F05-07). */
  steps?: AlternativesScenarioStep[];
  expected_summary?: {
    kind?: string;
    step1_swap?: { slot: string; to: string; setPartnerIds?: string[] };
    step2_slot?: string;
    step2_rankedGarmentIds?: string[];
    step2_emptyReason?: string | null;
    step2_must_exclude?: string[];
    [key: string]: unknown;
  };
}

export function loadJson<T>(absPath: string): T {
  return JSON.parse(readFileSync(absPath, "utf8")) as T;
}

export function listScenarioFiles(fixturesRoot: string): string[] {
  const dir = join(fixturesRoot, "scenarios");
  if (!existsSync(dir)) {
    throw new Error(`Scenarios directory not found: ${dir}`);
  }
  return readdirSync(dir)
    .filter(
      (f) =>
        f.endsWith(".json") &&
        !f.startsWith("._") &&
        !f.startsWith("index"),
    )
    .sort();
}

export function loadScenarioFile(
  fixturesRoot: string,
  fileName: string,
): ScenarioFile {
  return loadJson<ScenarioFile>(join(fixturesRoot, "scenarios", fileName));
}

export function loadSets(fixturesRoot: string): GarmentSet[] {
  const path = join(fixturesRoot, "wardrobe", "sets.json");
  if (!existsSync(path)) return [];
  return loadJson<GarmentSet[]>(path);
}

/** Default: outfit / T2 generate scenarios + multi-step alternatives (M1-F05). */
export function isOutfitTask(task: string | undefined, id: string): boolean {
  const t = (task ?? "").toUpperCase();
  if (t === "T2" || t === "OUTFIT") return true;
  if (!task && /^T2[-_]/.test(id)) return true;
  // M1-F05 alternatives / swap-rerank — match by scenario id (not index manifests)
  if (/^M1-F05/.test(id)) return true;
  return false;
}

/** True when fixture is the two-step alternatives_swap_rerank flow (M1-F05-07). */
export function isAlternativesSwapRerankScenario(
  scenario: Pick<ScenarioFile, "kind" | "task" | "id" | "steps">,
): boolean {
  if (scenario.kind === "alternatives_swap_rerank") return true;
  if ((scenario.task ?? "").toUpperCase() === "M1-F05" && Array.isArray(scenario.steps)) {
    return true;
  }
  if (/^M1-F05-07/.test(scenario.id) && Array.isArray(scenario.steps)) {
    return true;
  }
  return false;
}

/**
 * Resolve --scenarios to full scenario ids (filename without .json).
 * Accepts: all | T2-01,T2-02 | T2-0* | prefixes.
 */
export function resolveScenarioIds(
  fixturesRoot: string,
  selector: string | string[],
  taskFilter: (task: string | undefined, id: string) => boolean = isOutfitTask,
): string[] {
  const files = listScenarioFiles(fixturesRoot);
  const allIds = files.map((f) => f.replace(/\.json$/, ""));

  const parts = (Array.isArray(selector) ? selector : [selector])
    .flatMap((s) => String(s).split(","))
    .map((s) => s.trim())
    .filter(Boolean);

  const wantAll =
    parts.length === 0 ||
    (parts.length === 1 && parts[0].toLowerCase() === "all");

  const matched = new Set<string>();

  const addIfTask = (id: string) => {
    const sc = loadScenarioFile(fixturesRoot, `${id}.json`);
    if (taskFilter(sc.task, id)) matched.add(id);
  };

  if (wantAll) {
    for (const id of allIds) addIfTask(id);
    return [...matched].sort();
  }

  for (const part of parts) {
    if (part.toLowerCase() === "all") {
      for (const id of allIds) addIfTask(id);
      continue;
    }
    if (part.includes("*") || part.includes("?")) {
      const re = new RegExp(
        "^" +
          part
            .replace(/[.+^${}()|[\]\\]/g, "\\$&")
            .replace(/\*/g, ".*")
            .replace(/\?/g, ".") +
          "$",
      );
      for (const id of allIds) {
        if (re.test(id)) addIfTask(id);
      }
      continue;
    }
    if (allIds.includes(part)) {
      addIfTask(part);
      continue;
    }
    const hits = allIds.filter(
      (id) => id === part || id.startsWith(`${part}-`) || id.startsWith(part),
    );
    const tight = hits.filter(
      (id) => id === part || id.startsWith(`${part}-`),
    );
    const use = tight.length > 0 ? tight : hits;
    if (use.length === 0) {
      throw new Error(`Unknown scenario selector: ${part}`);
    }
    for (const id of use) addIfTask(id);
  }

  return [...matched].sort();
}

export function loadGarments(fixturesRoot: string): GarmentSummary[] {
  const path = join(fixturesRoot, "wardrobe", "garments.json");
  if (!existsSync(path)) return [];
  return loadJson<GarmentSummary[]>(path);
}

/**
 * Apply availability overrides. Missing override IDs are pulled from catalog
 * when provided (named SET_CONFLICT / laundry partner cases).
 */
export function applyAvailabilityOverrides(
  wardrobe: GarmentSummary[],
  overrides?: Record<string, string>,
  catalog?: GarmentSummary[],
): GarmentSummary[] {
  let result = wardrobe.map((g) => ({ ...g }));
  if (!overrides) return result;

  const present = new Set(result.map((g) => g.id));
  if (catalog) {
    for (const id of Object.keys(overrides)) {
      if (present.has(id)) continue;
      const fromCat = catalog.find((g) => g.id === id);
      if (fromCat) {
        result.push({ ...fromCat });
        present.add(id);
      }
    }
  }

  return result.map((g) => {
    if (overrides[g.id] != null) {
      return {
        ...g,
        availability: overrides[g.id] as GarmentSummary["availability"],
      };
    }
    return g;
  });
}

export function applyLocalDrafts(
  wardrobe: GarmentSummary[],
  draftIds?: string[],
): GarmentSummary[] {
  if (!draftIds?.length) return wardrobe;
  const set = new Set(draftIds);
  return wardrobe.map((g) =>
    set.has(g.id) ? { ...g, readiness: "DRAFT" } : g,
  );
}

export function requestFromScenario(
  scenario: ScenarioFile,
  fixturesRoot: string,
): LocalGenerateRequest {
  let wardrobe = scenario.inputs.wardrobe.map((g) => ({ ...g }));
  wardrobe = applyAvailabilityOverrides(
    wardrobe,
    scenario.inputs.fixture_overrides?.availability,
    loadGarments(fixturesRoot),
  );
  wardrobe = applyLocalDrafts(wardrobe, scenario.inputs.local_drafts);

  return {
    wardrobe,
    context: scenario.inputs.context,
    anchorGarmentId: scenario.inputs.anchorGarmentId,
    lockedAssignments: scenario.inputs.lockedAssignments ?? [],
    options: scenario.inputs.options,
    profile: scenario.inputs.profile ?? null,
    sets: scenario.inputs.sets ?? loadSets(fixturesRoot),
    boldness: scenario.inputs.boldness,
    asOfDate: scenario.inputs.context?.capturedAt,
  };
}

/**
 * Shared wardrobe / profile / sets / context for alternatives eval steps.
 * Applies the same availability + draft overrides as generate.
 */
export function alternativesBaseFromScenario(
  scenario: ScenarioFile,
  fixturesRoot: string,
): {
  wardrobe: GarmentSummary[];
  context: ContextSnapshot;
  profile: StyleProfilePayload | null | undefined;
  sets: GarmentSet[];
  options: LocalGenerateRequest["options"] | undefined;
  asOfDate: string | undefined;
} {
  let wardrobe = scenario.inputs.wardrobe.map((g) => ({ ...g }));
  wardrobe = applyAvailabilityOverrides(
    wardrobe,
    scenario.inputs.fixture_overrides?.availability,
    loadGarments(fixturesRoot),
  );
  wardrobe = applyLocalDrafts(wardrobe, scenario.inputs.local_drafts);
  return {
    wardrobe,
    context: scenario.inputs.context,
    profile: scenario.inputs.profile ?? null,
    sets: scenario.inputs.sets ?? loadSets(fixturesRoot),
    options: scenario.inputs.options,
    asOfDate: scenario.inputs.context?.capturedAt,
  };
}

/**
 * Apply apply_swap (and optional set partners) onto a copy of assignments.
 */
export function applySwapToAssignments(
  assignments: OutfitAssignment[],
  swap: {
    slot: string;
    garmentId: string;
    setPartnerIds?: string[];
  },
  wardrobe: GarmentSummary[],
): OutfitAssignment[] {
  const next = assignments.map((a) => ({ ...a }));
  const slotIdx = next.findIndex((a) => a.slot === swap.slot);
  if (slotIdx >= 0) {
    next[slotIdx] = {
      ...next[slotIdx],
      garmentId: swap.garmentId,
      gapReason: null,
    };
  } else {
    next.push({
      slot: swap.slot as OutfitAssignment["slot"],
      garmentId: swap.garmentId,
      isAnchor: false,
      isLocked: false,
      gapReason: null,
    });
  }
  for (const partnerId of swap.setPartnerIds ?? []) {
    const g = wardrobe.find((w) => w.id === partnerId);
    if (!g) continue;
    const pIdx = next.findIndex((a) => a.slot === g.slot);
    if (pIdx >= 0) {
      next[pIdx] = {
        ...next[pIdx],
        garmentId: partnerId,
        gapReason: null,
      };
    } else {
      next.push({
        slot: g.slot,
        garmentId: partnerId,
        isAnchor: false,
        isLocked: false,
        gapReason: null,
      });
    }
  }
  return next;
}

export function loadScenarioById(
  fixturesRoot: string,
  idOrPrefix: string,
): ScenarioFile {
  const files = listScenarioFiles(fixturesRoot);
  const file =
    files.find((f) => f === `${idOrPrefix}.json`) ??
    files.find(
      (f) => f.startsWith(`${idOrPrefix}-`) || f.startsWith(idOrPrefix),
    );
  if (!file) {
    throw new Error(`Scenario not found: ${idOrPrefix}`);
  }
  return loadScenarioFile(fixturesRoot, file);
}
