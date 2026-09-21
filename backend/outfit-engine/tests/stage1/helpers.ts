import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import type {
  GarmentSet,
  GarmentSummary,
  Stage1Input,
} from "../../src/types.js";

const __dirname = dirname(fileURLToPath(import.meta.url));
export const FIXTURES = join(__dirname, "../../../../fixtures");

export function loadJson<T>(rel: string): T {
  return JSON.parse(readFileSync(join(FIXTURES, rel), "utf8")) as T;
}

export function loadGarments(): GarmentSummary[] {
  return loadJson<GarmentSummary[]>("wardrobe/garments.json");
}

export function loadSets(): GarmentSet[] {
  return loadJson<GarmentSet[]>("wardrobe/sets.json");
}

export interface ScenarioFile {
  id: string;
  inputs: {
    wardrobe: GarmentSummary[];
    context: Stage1Input["context"];
    anchorGarmentId?: string | null;
    lockedAssignments?: Stage1Input["lockedAssignments"];
    options?: Stage1Input["options"];
    profile?: Stage1Input["profile"];
    sets?: GarmentSet[];
    fixture_overrides?: {
      availability?: Record<string, string>;
    };
    local_drafts?: string[];
  };
  expected: Record<string, unknown>;
}

export function loadScenario(id: string): ScenarioFile {
  return loadJson<ScenarioFile>(`scenarios/${id}.json`);
}

/**
 * Apply fixture_overrides.availability onto a wardrobe copy.
 * IDs present only in overrides (e.g. laundry partner omitted from embedded
 * wardrobe) are pulled from the catalog when provided so displayName + LAUNDRY
 * are available for named SET_CONFLICT reasons.
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
      return { ...g, availability: overrides[g.id] };
    }
    return g;
  });
}

export function stage1InputFromScenario(s: ScenarioFile): Stage1Input {
  let wardrobe = s.inputs.wardrobe.map((g) => ({ ...g }));
  wardrobe = applyAvailabilityOverrides(
    wardrobe,
    s.inputs.fixture_overrides?.availability,
    loadGarments(),
  );
  return {
    wardrobe,
    context: s.inputs.context,
    anchorGarmentId: s.inputs.anchorGarmentId,
    lockedAssignments: s.inputs.lockedAssignments ?? [],
    options: s.inputs.options,
    profile: s.inputs.profile,
    sets: s.inputs.sets ?? loadSets(),
  };
}

export function mildWorkContext(
  formality = 3,
): Stage1Input["context"] {
  return {
    occasion: "WORK_STANDARD",
    occasionFormality: formality,
    temperatureBand: "MILD",
    precipitation: false,
  };
}
