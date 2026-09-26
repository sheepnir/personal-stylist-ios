import type {
  BuilderInput,
  OutfitAssignment,
  Slot,
  Stage2Result,
  Stage4Caution,
  Stage4Input,
  Stage4ViolationCode,
} from "../types.js";

export type ProviderOutputFailureCause =
  | "OUTPUT_PARSE"
  | "OUTPUT_MODEL_MISMATCH"
  | "OUTPUT_SCHEMA"
  | "OUTPUT_TOKEN_MAP"
  | "OUTPUT_STAGE4"
  | "OUTPUT_EXCLUDED_SET"
  | "OUTPUT_LENGTH";

export interface ProviderChoiceQuestion {
  id: string;
  type: "choice";
  /** Option keys the model may return (includes `none` when the slot is optional). */
  options: Record<string, unknown>;
  slot: Slot;
}

export interface ProviderNoulQuestion {
  id: string;
  type: "noul";
  /** Garment token for this accessory candidate. */
  garmentToken: string;
}

export type ProviderQuestion = ProviderChoiceQuestion | ProviderNoulQuestion;

/**
 * `keepTogether` set offered as one `s_xx` option (ADR §7.1.2).
 * A-1 `outfit-t2-v1-optionDescriptions.ts` does not define this shape yet (fa3e825).
 */
export interface ProviderSetToken {
  /** Set token (`s_` + suffix) appearing in the first slot question's options. */
  token: string;
  /** Slot whose choice question lists `token` as an option key. */
  firstSlot: Slot;
  memberGarmentIds: string[];
  memberSlots: Slot[];
}

export interface DecisionsAnswerChoice {
  type: "choice";
  choice: string;
  confidence?: number;
  probabilities?: Record<string, number>;
}

export interface DecisionsAnswerNoul {
  type: "noul";
  noul: number;
  confidence?: number;
}

export type DecisionsAnswer = DecisionsAnswerChoice | DecisionsAnswerNoul;

export interface DecisionsUsage {
  input_tokens: number;
  output_tokens: number;
}

export interface ParsedDecisionsResponse {
  answers: Record<string, DecisionsAnswer>;
  model: string;
  usage: DecisionsUsage;
}

export interface ValidateProviderOutputInput {
  /** Raw provider HTTP body (JSON). */
  responseBody: string;
  expectedModelSlug: string;
  questions: ProviderQuestion[];
  tokenToGarmentId: Record<string, string>;
  setTokens?: ProviderSetToken[];
  /** Fixed anchor / lock rows before model-filled slots. */
  seedAssignments: OutfitAssignment[];
  stage4: Omit<Stage4Input, "assignments">;
  builderInput: BuilderInput;
  stage2: Stage2Result;
  excludeGarmentSets?: string[][] | null;
  /** Slots with role lock in fixed (for exclude-set semantics). */
  lockedSlots?: Slot[];
}

export interface ProviderRationale {
  summary: string;
  pairingNotes?: string[];
  teachingNote?: string | null;
  cautions?: string[];
}

export interface ValidateProviderOutputOk {
  ok: true;
  assignments: OutfitAssignment[];
  rationale: ProviderRationale;
  stage4Cautions: Stage4Caution[];
  usage: DecisionsUsage;
  model: string;
}

export interface ValidateProviderOutputFail {
  ok: false;
  cause: ProviderOutputFailureCause;
  stage4ViolationCodes?: Stage4ViolationCode[];
}

export type ValidateProviderOutputResult =
  | ValidateProviderOutputOk
  | ValidateProviderOutputFail;
