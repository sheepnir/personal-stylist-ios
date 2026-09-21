/** Minimal types for Stage 1 — aligned with OpenAPI GarmentSummary / GenerateRequest. */

export type Slot =
  | "TOP"
  | "BOTTOM"
  | "FOOTWEAR"
  | "MID_LAYER"
  | "JACKET"
  | "OUTERWEAR"
  | "ACCESSORY";

export type TemperatureBand = "COLD" | "COOL" | "MILD" | "WARM" | "HOT";
export type Season = "SPRING" | "SUMMER" | "FALL" | "WINTER";
export type Formality = 1 | 2 | 3 | 4 | 5;
export type Warmth = 1 | 2 | 3 | 4 | 5;

export type Availability =
  | "AVAILABLE"
  | "LAUNDRY"
  | "PACKED"
  | "LOANED"
  | "RETIRED"
  | string;

export type Readiness = "READY" | "DRAFT" | string;

export interface Color {
  family: string;
  hex?: string | null;
  name?: string | null;
}

export interface GarmentSummary {
  id: string;
  displayName: string;
  slot: Slot;
  category?: string | null;
  colorPrimary?: Color | null;
  colorSecondary?: Color | null;
  pattern?: string | null;
  materials?: string[];
  surface?: string | null;
  formality?: number | null;
  warmth?: number | null;
  seasons?: Season[];
  fit?: string | null;
  lastWornOn?: string | null;
  daysSinceIntake?: number | null;
  isFavorite?: boolean;
  wantToWearMore?: boolean;
  comfortIssue?: boolean;
  setId?: string | null;
  keepTogether?: boolean;
  /** Fixture / client field — re-checked even if client claims filtered. */
  availability?: Availability;
  readiness?: Readiness;
  archivedAt?: string | null;
  /** false / wishlist → never eligible (D-25). Default owned when omitted. */
  owned?: boolean;
  isWishlist?: boolean;
  /**
   * Per-field attribution confidence 0..1 when present (PRD §10.2 #16).
   * Fixture-only on the deterministic path; omitted or null means unused.
   */
  attributeConfidence?: Record<string, number> | null;
}

export interface GarmentSet {
  id: string;
  displayName?: string;
  keepTogether: boolean;
  memberGarmentIds: string[];
}

export interface ContextSnapshot {
  occasion: string;
  occasionFormality: number;
  temperatureBand: TemperatureBand;
  precipitation?: boolean;
  timeOfDay?: string | null;
  freeTextNote?: string | null;
  capturedAt?: string;
}

export interface OutfitAssignment {
  slot: Slot;
  garmentId?: string | null;
  isAnchor?: boolean;
  isLocked?: boolean;
  gapReason?: string | null;
}

export type Polarity = "LIKE" | "DISLIKE" | "AVOID_HARD";
export type PreferenceKind =
  | "COLOR"
  | "PATTERN"
  | "FIT"
  | "MATERIAL"
  | "COMBINATION"
  | "CATEGORY"
  | "OCCASION"
  | "COMFORT";

export interface PreferenceRule {
  id?: string | null;
  kind: PreferenceKind | string;
  polarity: Polarity | string;
  subject: Record<string, unknown>;
  scope: string;
  provenance?: string;
  supportingSignals?: number;
  active?: boolean;
}

export interface StyleProfilePayload {
  version?: number;
  summaryText?: string;
  experimentationLevel?: string;
  activeRules?: PreferenceRule[];
  [key: string]: unknown;
}

export interface Stage1Options {
  requireSlots?: Slot[];
  accessoryPolicy?: "OPEN" | "LOCKED";
  candidatesPerSlot?: number;
}

export interface Stage1Input {
  wardrobe: GarmentSummary[];
  context: ContextSnapshot;
  anchorGarmentId?: string | null;
  lockedAssignments?: OutfitAssignment[];
  options?: Stage1Options;
  profile?: StyleProfilePayload | null;
  /** Optional set catalog; also inferred from garment setId/keepTogether. */
  sets?: GarmentSet[];
}

export type RelaxationStep =
  | "FORMALITY_WIDENED"
  | "WARMTH_WIDENED"
  | "SLOT_ABANDONED";

export interface Relaxation {
  step: RelaxationStep;
  slot: Slot;
  note?: string | null;
}

export type Stage1ProblemCode =
  | "LOCK_CONFLICT"
  | "SET_CONFLICT"
  | "GARMENT_NOT_READY";

export interface Stage1Conflict {
  garmentId: string;
  role: string;
  slot?: Slot;
  availability?: string;
  reason?: string;
}

export interface Stage1Problem {
  ok: false;
  code: Stage1ProblemCode;
  title: string;
  status: 400;
  detail: string;
  conflicts?: Stage1Conflict[];
}

export interface Stage1Result {
  ok: true;
  /** Eligible garment ids per slot (stable-sorted). */
  eligible: Record<Slot, string[]>;
  /** Full garment objects per slot (same order as eligible ids). */
  eligibleGarments: Record<Slot, GarmentSummary[]>;
  relaxationsApplied: Relaxation[];
  gaps: Slot[];
  /** Anchor + locks that occupy slots. */
  fixed: { garmentId: string; slot: Slot; role: "anchor" | "lock" }[];
}

export type Stage1Output = Stage1Result | Stage1Problem;

export const DEFAULT_REQUIRE_SLOTS: Slot[] = ["TOP", "BOTTOM", "FOOTWEAR"];

export const ALL_SLOTS: Slot[] = [
  "TOP",
  "BOTTOM",
  "FOOTWEAR",
  "MID_LAYER",
  "JACKET",
  "OUTERWEAR",
  "ACCESSORY",
];

/** Base warmth tolerance by temperature band (PRD §8.2). */
export const WARMTH_TOLERANCE: Record<TemperatureBand, [Warmth, Warmth]> = {
  COLD: [3, 5],
  COOL: [2, 5],
  MILD: [1, 4],
  WARM: [1, 3],
  HOT: [1, 2],
};

/**
 * Seasons implied by temperatureBand (PRD §8.2).
 * Garment is eligible if seasons intersects this set, or garment is all-season.
 */
export const BAND_SEASONS: Record<TemperatureBand, Season[]> = {
  COLD: ["FALL", "WINTER"],
  COOL: ["SPRING", "FALL", "WINTER"],
  MILD: ["SPRING", "SUMMER", "FALL"],
  WARM: ["SPRING", "SUMMER"],
  HOT: ["SUMMER"],
};

export const ALL_SEASONS: Season[] = ["SPRING", "SUMMER", "FALL", "WINTER"];

// ---------------------------------------------------------------------------
// Stage 2 scoring + shortlist (M0-15)
// ---------------------------------------------------------------------------

export type Boldness = "FAMILIAR" | "SLIGHT_STRETCH" | "BOLD";

export interface ScoringWeights {
  w_color: number;
  w_texture: number;
  w_form: number;
  w_neglect: number;
  w_fav: number;
  w_weather: number;
  w_recent: number;
  w_repeat: number;
}

export interface ScoringConfig {
  weightsVersion: string;
  weights: ScoringWeights;
  shortlist: {
    defaultCap: number;
    minCap: number;
    maxCap: number;
    boldnessCaps: Record<Boldness, number>;
    ensureColourFamilyCoverage: boolean;
  };
  neglect: {
    horizonDays: number;
    wantToWearMoreMultiplier: number;
  };
  recency: {
    windowDays: number;
  };
  repeatPair: {
    windowDays: number;
  };
  color: {
    neutrals: string[];
    analogousGroups?: string[][];
    complementaryPairs?: string[][];
  };
  formality: {
    maxSpreadBeforeNearZero: number;
  };
  /** Optional clamp on total; omit / null = no clamp (default). */
  clampTotal?: [number, number] | null;
}

export interface ScoreBreakdown {
  components: Record<string, number>;
  weighted: Record<string, number>;
  total: number;
}

export interface ScoredCandidate {
  garmentId: string;
  slot: Slot;
  score: number;
  breakdown: ScoreBreakdown;
  setId?: string | null;
  setWith?: string[];
  overCapReason?: "SET_PARTNER" | "COLOUR_DIVERSITY" | "BOLD_STRETCH";
}

export interface CombinationExclusion {
  garmentId: string;
  slot: Slot;
  ruleId?: string | null;
  againstFixedId: string;
  reason: "COMBINATION_WITH_FIXED";
}

export interface WearHistoryEntry {
  garmentId: string;
  wornOn: string;
}

export interface SuggestedOutfitHistoryEntry {
  suggestedAt: string;
  garmentIds: string[];
}

export interface Stage2History {
  wears?: WearHistoryEntry[];
  suggestions?: SuggestedOutfitHistoryEntry[];
}

export interface Stage2Options {
  requireSlots?: Slot[];
  accessoryPolicy?: "OPEN" | "LOCKED";
  candidatesPerSlot?: number;
  /**
   * Test-only (T2-12): force this garment below the under-cap shortlist cutoff
   * so set expansion must pull it back with overCapReason SET_PARTNER.
   */
  force_weak_bottom_score_for?: string;
  /**
   * Client-sent garment id sets already shown this session (D-20 try-another).
   * Builder backtracks a free slot or returns `noAlternativeReason`.
   */
  excludeGarmentSets?: string[][];
}

export interface Stage2Input {
  wardrobe: GarmentSummary[];
  context: ContextSnapshot;
  profile?: StyleProfilePayload | null;
  boldness?: Boldness;
  options?: Stage2Options;
  sets?: GarmentSet[];
  history?: Stage2History | null;
  /** ISO date or datetime; defaults to context.capturedAt date or today. */
  asOfDate?: string;
}

export interface Stage2Result {
  ok: true;
  shortlist: Partial<Record<Slot, ScoredCandidate[]>>;
  candidateIds: Partial<Record<Slot, string[]>>;
  scores: Record<string, ScoreBreakdown>;
  excludedByCombination: CombinationExclusion[];
  setShortlistExpansions: {
    setId: string;
    pulledOverCap: { slot: Slot; garmentId: string }[];
  }[];
  colourDiversityExpansions?: { slot: Slot; garmentId: string }[];
  fixed: Stage1Result["fixed"];
  gaps: Slot[];
  relaxationsApplied: Relaxation[];
  meta: {
    capUsed: number;
    boldness: Boldness;
    weightsVersion: string;
    /** True if asOfDate was explicitly provided; false if fallback was used. */
    asOfDateProvided?: boolean;
  };
}

// ---------------------------------------------------------------------------
// Stage 3 deterministic builder (M0-16)
// ---------------------------------------------------------------------------

export interface BuilderConfig {
  fillOrder: Slot[];
  /** M0 default false — do not pull ACCESSORY from shortlist. */
  fillOptionalAccessories: boolean;
  /** Max accessories when fillOptionalAccessories is true. */
  maxAccessories: number;
  builderModelId: string;
  /** Assignment array order: FILL_ORDER with gap rows inline. */
  assignmentOrder: "FILL_ORDER_INLINE_GAPS";
}

export interface BuilderPlacedMeta {
  slot: Slot;
  garmentId: string;
  source: "fixed" | "shortlist" | "set_partner";
}

export interface BuilderSkippedMeta {
  slot: Slot;
  garmentId: string;
  reason: "COMBINATION" | "ALREADY_USED" | "SET_INCOMPLETE";
}

export interface BuilderMeta {
  fillOrder: Slot[];
  placed: BuilderPlacedMeta[];
  skipped: BuilderSkippedMeta[];
  gapsEmitted: Slot[];
  weightsVersion: string;
}

export interface BuilderResult {
  ok: true;
  outfitId: string;
  assignments: OutfitAssignment[];
  rationale: {
    summary: string;
    pairingNotes?: string[];
    teachingNote?: string | null;
    cautions?: string[];
  };
  boldnessUsed: Boldness;
  noAlternativeReason?: string | null;
  relaxationsApplied: Relaxation[];
  candidateSet?: Partial<
    Record<
      Slot,
      { garmentId: string; score: number | null; reason: string | null }[]
    >
  >;
  generation: {
    modelId: string;
    promptVersion: "none";
    candidateSetHash: string | null;
    latencyMs: number;
    inputTokens: null;
    outputTokens: null;
    costUSD: 0;
    repairAttempts: 0;
    fallbackLevel: "DETERMINISTIC";
    spendState?: "OK" | "HARD_CAP_DETERMINISTIC";
  };
  builderMeta: BuilderMeta;
}

/** Builder input — same request context Stage 1/2 saw. */
export type BuilderInput = Stage2Input;

// ---------------------------------------------------------------------------
// Stage 4 validation (M0-19)
// ---------------------------------------------------------------------------

export type Stage4ViolationCode =
  | "CANDIDATE_SET_MEMBERSHIP"
  | "ANCHOR_MISSING"
  | "ANCHOR_MISMATCH"
  | "SLOT_UNIQUENESS"
  | "ACCESSORY_LIMIT"
  | "DUPLICATE_GARMENT"
  | "REQUIRED_SLOT_EMPTY"
  | "COMBINATION_VIOLATION"
  | "SET_INTEGRITY"
  | "LOCK_MISSING"
  | "LOCK_MISMATCH"
  | "ACCESSORY_POLICY";

export type Stage4CautionCode =
  | "LOCKED_DISLIKED_PAIR"
  | "LAYER_REQUIREMENT"
  | "RATIONALE_QUALITY";

export interface Stage4Violation {
  code: Stage4ViolationCode;
  reason: string;
  slot?: Slot;
  garmentId?: string;
  relatedIds?: string[];
  ruleId?: string | null;
}

export interface Stage4Caution {
  code: Stage4CautionCode;
  reason: string;
  relatedIds?: string[];
}

export interface Stage4Options {
  requireSlots?: Slot[];
  accessoryPolicy?: "OPEN" | "LOCKED";
}

export interface Stage4Input {
  assignments: OutfitAssignment[];
  /** Preferred: Stage 2 candidate id lists per slot. */
  candidateIds?: Partial<Record<Slot, string[]>>;
  /** Builder-shaped candidate set (garmentId + score). */
  candidateSet?: BuilderResult["candidateSet"];
  fixed: Stage1Result["fixed"];
  wardrobe: GarmentSummary[];
  context: ContextSnapshot;
  profile?: StyleProfilePayload | null;
  sets?: GarmentSet[];
  options?: Stage4Options;
  /** Optional rationale for soft quality caution. */
  rationale?: BuilderResult["rationale"] | null;
  /** Optional fallback level to adjust validation rules. */
  fallbackLevel?: "DETERMINISTIC" | string;
}

export interface Stage4ResultOk {
  ok: true;
  cautions: Stage4Caution[];
}

export interface Stage4ResultFail {
  ok: false;
  violations: Stage4Violation[];
  cautions: Stage4Caution[];
}

export type Stage4Result = Stage4ResultOk | Stage4ResultFail;
