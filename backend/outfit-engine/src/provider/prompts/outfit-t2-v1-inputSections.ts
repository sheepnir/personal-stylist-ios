import type { StylistPromptInputSection } from "../promptVersionTypes.js";
import { deepFreeze } from "../promptImmutability.js";

/**
 * Human-readable descriptors of payload sections that accompany the instruction text.
 * These keys are for versioning/documentation only — they are NOT Decisions API question ids.
 * Question ids (slot_<SLOT>, accessory ids from the A-3 request builder) are defined in A-2/A-3.
 */
export const OUTFIT_T2_V1_INPUT_SECTIONS: readonly StylistPromptInputSection[] =
  deepFreeze([
    {
      sectionKey: "shortlist_attributes",
      description:
        "Shortlisted garments only: opaque tokens, slots, enums, and constraint flags. No names or UUIDs.",
    },
    {
      sectionKey: "occasion_context",
      description:
        "Occasion, formality, weather band, precipitation, and time-of-day enums for this request.",
    },
    {
      sectionKey: "style_profile",
      description:
        "Reduced style profile fields when enabled; empty in phase A until client profile send lands.",
    },
    {
      sectionKey: "generation_constraints",
      description:
        "Generation options such as requireSlots and accessoryPolicy that constrain assignments.",
    },
  ]);
