import type { Stage1Result, Stage2Input } from "../../src/types.js";
import { runStage1 } from "../../src/stage1/hardFilter.js";
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

export function runStage1FromScenario(
  id: string,
  testOnlyOptions?: { force_weak_bottom_score_for?: string },
): {
  scenario: ScenarioFile;
  stage1: Stage1Result;
  stage2Input: Stage2Input;
} {
  const scenario = loadScenario(id);
  const s1Input = stage1InputFromScenario(scenario);
  const out = runStage1(s1Input);
  if (!out.ok) {
    throw new Error(`Stage1 failed for ${id}: ${out.code} ${out.detail}`);
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
  return { scenario, stage1: out, stage2Input };
}
