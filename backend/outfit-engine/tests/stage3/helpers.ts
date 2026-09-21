import { runStage1 } from "../../src/stage1/hardFilter.js";
import { runStage2 } from "../../src/stage2/runStage2.js";
import { runBuilder } from "../../src/stage3/runBuilder.js";
import type {
  BuilderResult,
  Stage1Problem,
  Stage1Result,
  Stage2Input,
  Stage2Result,
} from "../../src/types.js";
import {
  loadScenario,
  stage1InputFromScenario,
  type ScenarioFile,
} from "../stage1/helpers.js";

export {
  loadGarments,
  loadSets,
  loadScenario,
  stage1InputFromScenario,
  mildWorkContext,
} from "../stage1/helpers.js";

export const WEIGHTS_VERSION = "1.0.0";

export function pipelineFromScenario(
  id: string,
  testOnlyOptions?: { force_weak_bottom_score_for?: string },
): {
  scenario: ScenarioFile;
  stage1: Stage1Result | Stage1Problem;
  stage2?: Stage2Result;
  builder?: BuilderResult;
} {
  const scenario = loadScenario(id);
  const s1Input = stage1InputFromScenario(scenario);
  const stage1 = runStage1(s1Input);
  if (!stage1.ok) {
    return { scenario, stage1 };
  }
  const opts = scenario.inputs.options as Stage2Input["options"] | undefined;
  const stage2Input: Stage2Input = {
    wardrobe: s1Input.wardrobe,
    context: s1Input.context,
    profile: s1Input.profile,
    sets: s1Input.sets,
    options: {
      requireSlots: opts?.requireSlots,
      accessoryPolicy: opts?.accessoryPolicy,
      candidatesPerSlot: opts?.candidatesPerSlot,
      force_weak_bottom_score_for: testOnlyOptions?.force_weak_bottom_score_for,
    },
    asOfDate: s1Input.context.capturedAt,
  };
  const stage2 = runStage2(stage1, stage2Input);
  const builder = runBuilder(stage2, stage2Input);
  return { scenario, stage1, stage2, builder };
}

export function assignmentMap(
  builder: BuilderResult,
): Record<string, string | null> {
  const out: Record<string, string | null> = {};
  for (const a of builder.assignments) {
    if (a.slot === "ACCESSORY") continue;
    out[a.slot] = a.garmentId ?? null;
  }
  return out;
}

export function filledIds(builder: BuilderResult): string[] {
  return builder.assignments
    .filter((a) => a.garmentId)
    .map((a) => a.garmentId!);
}
