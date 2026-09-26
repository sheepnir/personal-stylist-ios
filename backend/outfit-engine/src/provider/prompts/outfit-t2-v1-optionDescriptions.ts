import type { StylistPromptOptionDescription } from "../promptVersionTypes.js";

/** Static option descriptions for the outfit-t2-v1 Decisions request (hashed with the version). */
export const OUTFIT_T2_V1_OPTION_DESCRIPTIONS: readonly StylistPromptOptionDescription[] =
  [
    {
      id: "candidates",
      description:
        "Shortlisted garments only: opaque tokens, slots, enums, and constraint flags. No names or UUIDs.",
    },
    {
      id: "context",
      description:
        "Occasion, formality, weather band, precipitation, and time-of-day enums for this request.",
    },
    {
      id: "profile",
      description:
        "Reduced style profile fields when enabled; empty in phase A until client profile send lands.",
    },
    {
      id: "options",
      description:
        "Generation options such as requireSlots and accessoryPolicy that constrain assignments.",
    },
  ] as const;
