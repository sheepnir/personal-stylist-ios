export { runEval, evaluateScenario } from "./run.js";
export {
  compareExpected,
  compareAlternativesStep,
  assertOrderDiffers,
  resultFingerprint,
  alternativesFingerprint,
} from "./compare.js";
export {
  defaultFixturesRoot,
  resolveScenarioIds,
  loadScenarioById,
  requestFromScenario,
  alternativesBaseFromScenario,
  applySwapToAssignments,
  isOutfitTask,
  isAlternativesSwapRerankScenario,
} from "./scenarios.js";
export { formatTable, formatJsonSummary } from "./report.js";
export type {
  EvalReport,
  RunEvalOptions,
  ScenarioEvalResult,
  OutcomeClassification,
} from "./types.js";
export type {
  ScenarioFile,
  ScenarioExpected,
  AlternativesScenarioStep,
} from "./scenarios.js";
