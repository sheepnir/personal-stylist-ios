/** Fixed summary for provider-backed generation (ADR §7.1.4). */
export const PROVIDER_PATH_RATIONALE_SUMMARY =
  "Outfit slots were chosen by the stylist model; the notes below are assembled from your wardrobe, not written by the model.";

/** Include accessory when a noul answer is at or above this value (mock default is 0.5). */
export const NOUL_ACCESSORY_THRESHOLD = 0.5;

export const RATIONALE_LIMITS = {
  summary: 200,
  pairingNote: 140,
  teachingNote: 160,
  caution: 120,
} as const;
